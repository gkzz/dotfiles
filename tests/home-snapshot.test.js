import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it } from "node:test";

import { repositoryRoot, run } from "./helpers/process.js";

const snapshotCommand = path.join(
  repositoryRoot,
  "tests/integration/home-snapshot.sh",
);

function encode(value) {
  return Buffer.from(value).toString("hex");
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function fixture(t) {
  const root = realpathSync(
    mkdtempSync(path.join(os.tmpdir(), "home-snapshot-test.")),
  );
  const home = path.join(root, "home");
  mkdirSync(home);
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return { root, home, output: path.join(root, "snapshot") };
}

function snapshot(home, output, options = {}) {
  return run(snapshotCommand, [home, output], options);
}

describe("HOME snapshot", () => {
  it("UTF-8でないファイル名とsymlink参照先も保持する", (t) => {
    const { home, output } = fixture(t);
    const name = Buffer.from([0xff, 0x0a, 0x09]);
    const file = Buffer.concat([Buffer.from(`${home}/`), name]);
    const target = Buffer.from([0xfe, 0x0a]);
    try {
      symlinkSync(target, file);
    } catch (error) {
      if (error.code === "EILSEQ") {
        return t.skip("ファイルシステムがUTF-8でない名前を作成できない");
      }
      throw error;
    }
    assert.equal(snapshot(home, output).status, 0);
    assert.equal(readFileSync(output, "utf8"), "ff0a09\tl\tfe0a\n");
  });

  it("ファイルとディレクトリの権限だけの変更も検出する", (t) => {
    const { home, output } = fixture(t);
    const file = path.join(home, "file");
    const directory = path.join(home, "directory");
    writeFileSync(file, "unchanged");
    mkdirSync(directory);
    chmodSync(file, 0o600);
    chmodSync(directory, 0o700);
    assert.equal(snapshot(home, output).status, 0);
    const before = readFileSync(output, "utf8");
    chmodSync(file, 0o644);
    assert.equal(snapshot(home, output).status, 0);
    const changedFile = readFileSync(output, "utf8");
    assert.notEqual(changedFile, before);
    chmodSync(directory, 0o755);
    assert.equal(snapshot(home, output).status, 0);
    assert.notEqual(readFileSync(output, "utf8"), changedFile);
  });

  it("読み取れないファイルでは失敗し、既存snapshotを置き換えない", (t) => {
    if (process.getuid?.() === 0)
      return t.skip("rootはファイル権限を越えて読み取れる");
    const { home, output } = fixture(t);
    const file = path.join(home, "unreadable");
    writeFileSync(file, "content");
    chmodSync(file, 0o000);
    writeFileSync(output, "previous snapshot");
    const result = snapshot(home, output);
    assert.notEqual(result.status, 0, result.stderr);
    assert.match(result.stderr, /EACCES/);
    assert.equal(readFileSync(output, "utf8"), "previous snapshot");
  });

  it("列挙後に消えたentryでは失敗し、既存snapshotを置き換えない", (t) => {
    const { root, home, output } = fixture(t);
    writeFileSync(output, "previous snapshot");
    const bin = path.join(root, "bin");
    mkdirSync(bin);
    const fakeFind = path.join(bin, "find");
    writeFileSync(
      fakeFind,
      `#!/usr/bin/env bash
printf '%s\\0' "$1/missing"
`,
    );
    chmodSync(fakeFind, 0o755);
    const result = snapshot(home, output, {
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
    });
    assert.notEqual(result.status, 0, result.stderr);
    assert.match(result.stderr, /ENOENT/);
    assert.equal(readFileSync(output, "utf8"), "previous snapshot");
  });

  it("entryの種別と任意のbyteをOS非依存のrecordへ正規化する", (t) => {
    const { home, output } = fixture(t);
    const same = Buffer.from("same\n");
    const different = Buffer.from("different\n");
    const unusual = "line\nwith\ttab space\\name";
    const linkTarget = "target\nwith\ttab\\text\n";

    mkdirSync(path.join(home, "directory"));
    chmodSync(path.join(home, "directory"), 0o755);
    writeFileSync(path.join(home, "same-a"), same);
    writeFileSync(path.join(home, "same-b"), same);
    writeFileSync(path.join(home, unusual), different);
    for (const file of ["same-a", "same-b", unusual]) {
      chmodSync(path.join(home, file), 0o644);
    }
    symlinkSync(linkTarget, path.join(home, "link"));

    const result = snapshot(home, output);
    assert.equal(result.status, 0, result.stderr);
    const expected = [
      `${encode("directory")}\td\t755`,
      `${encode("same-a")}\tf\t644\t${sha256(same)}`,
      `${encode("same-b")}\tf\t644\t${sha256(same)}`,
      `${encode(unusual)}\tf\t644\t${sha256(different)}`,
      `${encode("link")}\tl\t${encode(linkTarget)}`,
    ].sort();
    assert.deepEqual(
      readFileSync(output, "utf8").trimEnd().split("\n"),
      expected,
    );
  });

  it("列挙順に依存せず、内容とsymlink文字列の変更を検出する", (t) => {
    const { root, home, output } = fixture(t);
    writeFileSync(path.join(home, "z"), "same\n");
    writeFileSync(path.join(home, "a"), "same\n");
    symlinkSync("z", path.join(home, "link"));
    assert.equal(snapshot(home, output).status, 0);
    const first = readFileSync(output);

    const records = readFileSync(output, "utf8").trimEnd().split("\n");
    assert.deepEqual(records, [...records].sort());

    writeFileSync(path.join(home, "z"), "changed\n");
    rmSync(path.join(home, "link"));
    symlinkSync("a", path.join(home, "link"));
    const changedOutput = path.join(root, "changed-snapshot");
    assert.equal(snapshot(home, changedOutput).status, 0);
    assert.notDeepEqual(readFileSync(changedOutput), first);
  });

  it("危険または曖昧なHOMEとOUTPUTを拒否する", async (t) => {
    const { root, home, output } = fixture(t);
    const linkedHome = path.join(root, "linked-home");
    symlinkSync(home, linkedHome);
    const cases = [
      ["empty HOME", "", output],
      ["relative HOME", "relative", output],
      ["root HOME", "/", output],
      ["symlink HOME", linkedHome, output],
      ["OUTPUT below HOME", home, path.join(home, "snapshot")],
    ];
    for (const [name, candidateHome, candidateOutput] of cases) {
      await t.test(name, () => {
        const result = snapshot(candidateHome, candidateOutput);
        assert.notEqual(result.status, 0, result.stderr);
      });
    }
  });

  it("未対応のentry種別を拒否する", (t) => {
    const { home, output } = fixture(t);
    const fifo = path.join(home, "fifo");
    const created = spawnSync("mkfifo", [fifo], { encoding: "utf8" });
    assert.equal(created.status, 0, created.stderr);
    const result = snapshot(home, output);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /unsupported entry type/);
  });

  it("findが一部を列挙してから失敗した場合も失敗する", (t) => {
    const { root, home, output } = fixture(t);
    const partial = path.join(home, "partial");
    writeFileSync(partial, "content");
    const bin = path.join(root, "bin");
    mkdirSync(bin);
    const fakeFind = path.join(bin, "find");
    writeFileSync(
      fakeFind,
      `#!/usr/bin/env bash
printf '%s\\0' "$1/partial"
printf '%s\\n' 'fake find failure' >&2
exit 19
`,
    );
    chmodSync(fakeFind, 0o755);

    const result = snapshot(home, output, {
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
    });
    assert.equal(result.status, 19, result.stderr);
    assert.match(result.stderr, /fake find failure/);
  });
});

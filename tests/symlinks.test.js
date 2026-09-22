import assert from "node:assert/strict";
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  readlinkSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";

import { TestFixture } from "./helpers/fixture.js";
import { repositoryRoot, run } from "./helpers/process.js";

/**
 * managed symlink の安全性を検証する。
 * 競合時に利用者のファイルを壊さないこと、--force の backup と rollback、
 * 検証後に destination が変わる競合、clone path に依存しない設定解決が対象。
 */
const text = (file) => readFileSync(file, "utf8");
const seeds = JSON.parse(
  readFileSync(
    path.join(repositoryRoot, "tests/fixtures/inputs/symlinks.json"),
    "utf8",
  ),
);
const backups = (home, name) =>
  readdirSync(home)
    .filter((entry) => entry.startsWith(`${name}.backup.`))
    .map((entry) => path.join(home, entry));

describe("managed resources", () => {
  describe("verify", () => {
    it("reports each managed symlink mismatch without repairing it", async (t) => {
      const cases = [
        {
          name: "missing",
          arrange(destination) {
            rmSync(destination);
          },
          message: "managed symlink is missing",
          verify(destination) {
            assert.equal(existsSync(destination), false);
          },
        },
        {
          name: "regular file",
          arrange(destination) {
            rmSync(destination);
            writeFileSync(destination, "keep this local file\n");
          },
          message: "managed destination is not a symlink",
          verify(destination) {
            assert.equal(text(destination), "keep this local file\n");
          },
        },
        {
          name: "directory",
          arrange(destination) {
            rmSync(destination);
            mkdirSync(destination);
          },
          message: "managed destination is not a symlink",
          verify(destination) {
            assert.equal(lstatSync(destination).isDirectory(), true);
          },
        },
        {
          name: "wrong target",
          arrange(destination, home) {
            rmSync(destination, { recursive: true });
            symlinkSync(path.join(home, "wrong-target"), destination);
          },
          message: "managed symlink target differs",
          verify(destination, home) {
            assert.equal(
              readlinkSync(destination),
              path.join(home, "wrong-target"),
            );
          },
        },
      ];

      for (const scenario of cases) {
        await t.test(scenario.name, (t) => {
          const fixture = new TestFixture(t);
          const home = fixture.createConvergedHome("home");
          const destination = path.join(home, ".bashrc");
          scenario.arrange(destination, home);

          const result = fixture.runDotfiles(home, ["verify", "--skip-brew"]);

          assert.equal(result.status, 1, result.stderr);
          assert.match(
            result.stderr,
            new RegExp(
              `verify failed: ${scenario.message}: path=${destination.replaceAll(".", "\\.")} expected=${path.join(repositoryRoot, ".bashrc").replaceAll(".", "\\.")}`,
            ),
          );
          if (scenario.name === "wrong target") {
            assert.match(
              result.stderr,
              new RegExp(
                `actual=${path.join(home, "wrong-target").replaceAll(".", "\\.")}`,
              ),
            );
          }
          scenario.verify(destination, home);
        });
      }
    });

    it("reports readlink execution errors without misclassifying the target", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.createConvergedHome("home");
      const destination = path.join(home, ".bashrc");
      const failureBin = path.join(fixture.root, "failure-bin");
      const fakeReadlink = path.join(failureBin, "readlink");
      mkdirSync(failureBin);
      writeFileSync(
        fakeReadlink,
        `#!/usr/bin/env bash
set -euo pipefail
if [ "\${FAIL_READLINK_PATH:-}" = "\${1:-}" ]; then
  printf '%s\\n' 'fake readlink failure' >&2
  exit 20
fi
exec /usr/bin/readlink "$@"
`,
      );
      chmodSync(fakeReadlink, 0o755);

      const result = fixture.runDotfiles(home, ["verify", "--skip-brew"], {
        TEST_PATH_PREFIX: failureBin,
        FAIL_READLINK_PATH: destination,
      });

      assert.equal(result.status, 1, result.stderr);
      assert.match(
        result.stderr,
        new RegExp(
          `verify error: failed to read managed symlink target: path=${destination.replaceAll(".", "\\.")}`,
        ),
      );
      assert.doesNotMatch(result.stderr, /managed symlink target differs/);
      assert.equal(
        readlinkSync(destination),
        path.join(repositoryRoot, ".bashrc"),
      );
    });
  });

  it("reject malformed resource definitions before lifecycle work", () => {
    const cases = [
      {
        name: "incomplete triple",
        definition: "MANAGED_RESOURCES=(symlink source)",
        message: "type/source/destination triples",
      },
      {
        name: "unknown type",
        definition: "MANAGED_RESOURCES=(file source destination)",
        message: "unknown managed resource type",
      },
      {
        name: "empty source",
        definition: 'MANAGED_RESOURCES=(symlink "" destination)',
        message: "source must not be empty",
      },
      {
        name: "empty destination",
        definition: 'MANAGED_RESOURCES=(symlink source "")',
        message: "destination must not be empty",
      },
      {
        name: "duplicate destination",
        definition:
          "MANAGED_RESOURCES=(symlink source-a destination symlink source-b destination)",
        message: "destination is duplicated",
      },
    ];

    for (const scenario of cases) {
      const script = `
        . "$1/setup/lib.bash"
        . "$1/setup/symlinks.bash"
        ${scenario.definition}
        validate_managed_resources_definition
      `;
      const result = run("bash", ["-c", script, "_", repositoryRoot]);
      assert.notEqual(result.status, 0, scenario.name);
      assert.match(result.stderr, new RegExp(scenario.message), scenario.name);
    }
  });

  it("handle conflicts, backups, and concurrent changes", (t) => {
    const fixture = new TestFixture(t);
    const home = fixture.createConvergedHome("home");
    const gitconfig = path.join(home, ".gitconfig");

    rmSync(gitconfig);
    writeFileSync(gitconfig, seeds.conflict.gitconfig);
    writeFileSync(path.join(home, "calls"), "");
    let result = fixture.runDotfiles(home, ["install", "--apply"]);
    // 通常の install は競合ファイルを保持し、package操作へ進まない。
    assert.equal(result.status, 1);
    assert.equal(text(gitconfig), "local git config\n");
    assert.doesNotMatch(text(path.join(home, "calls")), /brew |mise /);
    assert.equal(
      existsSync(path.join(home, ".local/state/dotfiles/lifecycle.lock")),
      false,
    );

    const revalidationHome = fixture.newHome("revalidation-home");
    result = fixture.runDotfiles(
      revalidationHome,
      ["install", "--skip-brew", "--dry-run"],
      {
        CREATE_DESTINATION_DURING_PREFLIGHT: path.join(
          revalidationHome,
          ".bashrc",
        ),
      },
    );
    // preflight後に現れたファイルを、未検証のreplace actionへ昇格させない。
    assert.equal(result.status, 1);
    assert.match(
      result.stderr,
      new RegExp(`destination conflict: ${revalidationHome}/\\.bashrc`),
    );
    assert.doesNotMatch(result.stdout, /plan: replace_symlink/);
    assert.equal(
      text(path.join(revalidationHome, ".bashrc")),
      "created during package validation\n",
    );

    result = fixture.runDotfiles(home, ["install", "--force", "--dry-run"]);
    // dry-runはbackupを作らず、applyだけが元ファイルを保存して収束させる。
    assert.equal(result.status, 0, result.stderr);
    assert.match(
      result.stdout,
      new RegExp(`plan: replace_symlink ${gitconfig}`),
    );
    assert.equal(lstatSync(gitconfig).isSymbolicLink(), false);
    assert.deepEqual(backups(home, ".gitconfig"), []);
    result = fixture.runDotfiles(home, ["install", "--force", "--apply"]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(lstatSync(gitconfig).isSymbolicLink(), true);
    assert.equal(backups(home, ".gitconfig").length, 1);

    const cases = [
      {
        name: "rollback-home",
        initial: seeds.ensure_symlink.rollback.initial,
        body: 'ln() { [ "$1" != "-s" ] && { command ln "$@"; return; }; return 1; }',
        expected: seeds.ensure_symlink.rollback.expected,
        backupCount: 0,
        planned: "",
      },
      {
        name: "concurrent-home",
        initial: seeds.ensure_symlink.concurrent.initial,
        body: 'ln() { if [ "$1" = "-s" ]; then printf "%s\\n" "concurrent replacement" > "$3"; return 1; fi; command ln "$@"; }',
        expected: seeds.ensure_symlink.concurrent.expected,
        backupCount: 1,
        planned: "",
      },
      {
        name: "planned-missing-home",
        initial: null,
        body: 'ln() { printf "%s\\n" "concurrent missing-plan replacement" > "$3"; return 1; }',
        expected: seeds.ensure_symlink.planned_missing.expected,
        backupCount: 0,
        planned: "ensure_symlink",
      },
    ];
    for (const scenario of cases) {
      const targetHome = path.join(fixture.root, scenario.name);
      mkdirSync(targetHome);
      if (scenario.initial !== null)
        writeFileSync(path.join(targetHome, ".bashrc"), scenario.initial);
      const script = `
    . "$1/setup/lib.bash"
    . "$1/setup/symlinks.bash"
    force=true
    ${scenario.body}
  ensure_symlink "$1/.bashrc" "$2/.bashrc" ${scenario.planned}
  `;
      result = run("bash", ["-c", script, "_", repositoryRoot, targetHome]);
      // symlink作成が失敗しても、同時に現れたdestinationを上書きしない。
      assert.equal(result.status, 1, `${scenario.name}: ${result.stderr}`);
      assert.equal(text(path.join(targetHome, ".bashrc")), scenario.expected);
      assert.equal(backups(targetHome, ".bashrc").length, scenario.backupCount);
    }
    assert.equal(
      text(backups(path.join(fixture.root, "concurrent-home"), ".bashrc")[0]),
      "preserve in backup\n",
    );

    const profile = path.join(home, ".bash_profile");
    rmSync(profile);
    mkdirSync(profile);
    writeFileSync(path.join(home, "calls"), "");
    result = fixture.runDotfiles(home, ["install", "--force", "--apply"]);
    assert.equal(result.status, 1);
    assert.equal(lstatSync(profile).isDirectory(), true);
    assert.doesNotMatch(
      text(path.join(home, "calls")),
      /brew bundle|mise install/,
    );
  });

  it("discover the repository without a clone-specific path", (t) => {
    const fixture = new TestFixture(t);
    const home = path.join(fixture.root, "discovery-home");
    mkdirSync(home);
    symlinkSync(
      path.join(repositoryRoot, ".bashrc"),
      path.join(home, ".bashrc"),
    );
    const result = run("env", [
      "-u",
      "DOTFILES",
      `HOME=${home}`,
      "bash",
      "--noprofile",
      "--norc",
      "-c",
      '. "$HOME/.bashrc"; printf "%s" "$DOTFILES"',
    ]);
    // 管理symlinkからrepositoryを逆算し、特定のclone先を設定へ埋め込まない。
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, repositoryRoot);
    assert.doesNotMatch(
      text(path.join(repositoryRoot, ".bashrc")),
      /github\.com\/gkzz\/dotfiles/,
    );
    const config = text(path.join(repositoryRoot, ".config/mise/config.toml"));
    assert.doesNotMatch(config, /github\.com\/gkzz\/dotfiles/);
    assert.match(config, /DOTFILES = "\{\{ config_source \| canonicalize/);
    assert.equal(
      readlinkSync(path.join(home, ".bashrc")),
      path.join(repositoryRoot, ".bashrc"),
    );
  });
});

import assert from "node:assert/strict";
import {
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

import { TestFixture } from "./helpers/fixture.mjs";
import { repositoryRoot, run } from "./helpers/process.mjs";

/**
 * managed symlink の安全性を検証する。
 * 競合時に利用者のファイルを壊さないこと、--force の backup と rollback、
 * 検証後に destination が変わる競合、clone path に依存しない設定解決が対象。
 */
const text = (file) => readFileSync(file, "utf8");
const backups = (home, name) =>
  readdirSync(home)
    .filter((entry) => entry.startsWith(`${name}.backup.`))
    .map((entry) => path.join(home, entry));

describe("managed resources", () => {
  it("handle conflicts, backups, and concurrent changes", (t) => {
    const fixture = new TestFixture(t);
    const home = fixture.createConvergedHome("home");
    const gitconfig = path.join(home, ".gitconfig");

    rmSync(gitconfig);
    writeFileSync(gitconfig, "local git config\n");
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
        initial: "restore me\n",
        body: 'ln() { [ "$1" != "-s" ] && { command ln "$@"; return; }; return 1; }',
        expected: "restore me\n",
        backupCount: 0,
        planned: "",
      },
      {
        name: "concurrent-home",
        initial: "preserve in backup\n",
        body: 'ln() { if [ "$1" = "-s" ]; then printf "%s\\n" "concurrent replacement" > "$3"; return 1; fi; command ln "$@"; }',
        expected: "concurrent replacement\n",
        backupCount: 1,
        planned: "",
      },
      {
        name: "planned-missing-home",
        initial: null,
        body: 'ln() { printf "%s\\n" "concurrent missing-plan replacement" > "$3"; return 1; }',
        expected: "concurrent missing-plan replacement\n",
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
    . "$1/setup/resources.bash"
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
    assert.match(config, /DOTFILES = "\{\{ \[xdg_config_home/);
    assert.equal(
      readlinkSync(path.join(home, ".bashrc")),
      path.join(repositoryRoot, ".bashrc"),
    );
  });
});

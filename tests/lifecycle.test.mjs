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
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";

import { TestFixture } from "./helpers/fixture.mjs";
import { assertBefore, repositoryRoot, run } from "./helpers/process.mjs";

/**
 * install / uninstall lifecycle の利用者向け契約を検証する。
 * planの一貫性、冪等性、lockの境界、既存データの保持、
 * package managerがない環境でもuninstallできることが対象。
 */
const text = (file) => readFileSync(file, "utf8");
const plans = (output) =>
  output.split("\n").filter((line) => line.startsWith("plan:"));
const backups = (home, name) =>
  readdirSync(home).filter((entry) => entry.startsWith(`${name}.backup.`));
const mode = (target) => statSync(target).mode & 0o777;

describe("dotfiles lifecycle", () => {
  describe("install", () => {
    it("keeps dry-run and apply plans equal and converges idempotently", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.newHome("home");
      const dry = fixture.runDotfiles(home, ["install", "--dry-run"]);
      assert.equal(dry.status, 0, dry.stderr);
      assert.match(
        dry.stdout,
        new RegExp(`plan: brew_bundle ${repositoryRoot}/Brewfile`),
      );
      assert.match(
        dry.stdout,
        new RegExp(
          `plan: mise_install ${repositoryRoot}/.config/mise/config.toml`,
        ),
      );
      assert.match(
        dry.stdout,
        new RegExp(`plan: ensure_symlink ${home}/.bashrc`),
      );
      assert.equal(existsSync(path.join(home, ".bashrc")), false);
      assert.equal(existsSync(path.join(home, ".local/state/dotfiles")), false);
      let calls = text(path.join(home, "calls"));
      assert.doesNotMatch(calls, /brew bundle/);
      assert.match(calls, /mise install --locked --dry-run/);
      assert.match(calls, /mise-env=unset/);

      const apply = fixture.runDotfiles(home, ["install", "--apply"]);
      // dry-runとapplyは同じplanを示し、applyだけがHOMEを変更する。
      assert.equal(apply.status, 0, apply.stderr);
      assert.deepEqual(plans(apply.stdout), plans(dry.stdout));
      for (const name of [
        ".bashrc",
        ".bash_profile",
        ".gitconfig",
        ".config/mise/config.toml",
      ]) {
        assert.equal(
          lstatSync(path.join(home, name)).isSymbolicLink(),
          true,
          name,
        );
      }
      assert.equal(
        readlinkSync(path.join(home, ".bashrc")),
        path.join(repositoryRoot, ".bashrc"),
      );
      assert.equal(
        existsSync(path.join(home, ".local/state/dotfiles/resources.tsv")),
        false,
      );
      calls = text(path.join(home, "calls"));
      assert.match(calls, /brew bundle --file .*Brewfile --no-upgrade/);
      assert.match(calls, /mise install --locked --yes node-version=unset/);
      assertBefore(
        calls,
        "brew bundle --file",
        "mise install --locked --yes",
        "package apply order",
      );
      assertBefore(
        dry.stdout,
        "plan: mise_install",
        "plan: ensure_symlink",
        "install plan order",
      );

      const repeated = fixture.runDotfiles(home, ["install", "--apply"]);
      // 収束後の再実行ではbackupを増やさない。
      assert.equal(repeated.status, 0, repeated.stderr);
      assert.deepEqual(backups(home, ".bashrc"), []);
    });
  });

  describe("lifecycle lock", () => {
    it("rejects unsafe ownership and recovers safe stale locks", (t) => {
      const fixture = new TestFixture(t);
      const lockHome = fixture.newHome("lock-home");
      mkdirSync(path.join(lockHome, ".dotfiles-lifecycle.lock"));
      writeFileSync(
        path.join(lockHome, ".dotfiles-lifecycle.lock/pid"),
        `${process.pid}\n`,
      );
      let result = fixture.runDotfiles(lockHome, ["install", "--apply"], {
        XDG_STATE_HOME: path.join(lockHome, "alternate-state"),
      });
      // lockはXDG_STATE_HOMEではなく、操作対象のHOMEごとに排他する。
      assert.equal(result.status, 1);
      assert.equal(existsSync(path.join(lockHome, ".bashrc")), false);
      assert.equal(existsSync(path.join(lockHome, "calls")), false);

      const pidHome = path.join(fixture.root, "pid-failure-home");
      mkdirSync(pidHome);
      result = run("bash", [
        "-c",
        `
              DOTFILES="$1"; HOME="$2"
              . "$DOTFILES/setup/lifecycle.bash"
              initialize_setup_context
              printf() { return 1; }
              lifecycle_lock_acquire
              `,
        "_",
        repositoryRoot,
        pidHome,
      ]);
      assert.equal(result.status, 1, result.stderr);
      assert.equal(
        existsSync(path.join(pidHome, ".dotfiles-lifecycle.lock")),
        false,
      );

      const staleHome = path.join(fixture.root, "stale-lock-home");
      mkdirSync(path.join(staleHome, ".dotfiles-lifecycle.lock"), {
        recursive: true,
      });
      writeFileSync(
        path.join(staleHome, ".dotfiles-lifecycle.lock/pid"),
        "99999999\n",
      );
      result = fixture.runDotfiles(staleHome, ["uninstall", "--apply"]);
      // 所有者がいない既知の形式のlockだけを自動回収する。
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stdout, /recovered stale lifecycle lock/);
      assert.equal(
        existsSync(path.join(staleHome, ".dotfiles-lifecycle.lock")),
        false,
      );

      const blockedHome = path.join(fixture.root, "blocked-stale-home");
      mkdirSync(path.join(blockedHome, ".dotfiles-lifecycle.lock"), {
        recursive: true,
      });
      writeFileSync(
        path.join(blockedHome, ".dotfiles-lifecycle.lock/pid"),
        "99999999\n",
      );
      writeFileSync(
        path.join(blockedHome, ".dotfiles-lifecycle.lock/extra"),
        "unexpected\n",
      );
      result = fixture.runDotfiles(blockedHome, ["uninstall", "--apply"]);
      // 未知のentryがあるlockは、調査に必要なmetadataを残して停止する。
      assert.equal(result.status, 1);
      assert.equal(
        text(path.join(blockedHome, ".dotfiles-lifecycle.lock/extra")),
        "unexpected\n",
      );

      const noopHome = path.join(fixture.root, "noop-home");
      mkdirSync(noopHome);
      result = fixture.runDotfiles(noopHome, ["uninstall", "--apply"]);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(existsSync(path.join(noopHome, ".local")), false);
    });

    it("does not follow symlinked boundaries or change permissions", (t) => {
      const fixture = new TestFixture(t);
      const lockHome = path.join(fixture.root, "symlink-lock-home");
      const lockTarget = path.join(fixture.root, "symlink-lock-target");
      mkdirSync(lockHome);
      mkdirSync(lockTarget);
      chmodSync(lockTarget, 0o755);
      symlinkSync(lockTarget, path.join(lockHome, ".dotfiles-lifecycle.lock"));
      const before = mode(lockTarget);
      let result = fixture.runDotfiles(lockHome, ["uninstall", "--apply"]);
      // HOME内のsymlinkをlock処理がたどって外部を書き換えない。
      assert.equal(result.status, 1);
      assert.equal(mode(lockTarget), before);
      assert.equal(existsSync(path.join(lockTarget, "lifecycle.lock")), false);

      const realHome = path.join(fixture.root, "real-home");
      const linkedHome = path.join(fixture.root, "linked-home");
      mkdirSync(realHome);
      symlinkSync(realHome, linkedHome);
      result = fixture.runDotfiles(linkedHome, ["uninstall", "--apply"]);
      assert.equal(result.status, 1);
      assert.equal(
        existsSync(path.join(realHome, ".dotfiles-lifecycle.lock")),
        false,
      );

      const lockDirHome = path.join(fixture.root, "linked-lock-dir-home");
      const lockDirTarget = path.join(fixture.root, "linked-lock-dir-target");
      mkdirSync(lockDirHome);
      mkdirSync(lockDirTarget);
      writeFileSync(path.join(lockDirTarget, "pid"), "99999999\n");
      symlinkSync(
        lockDirTarget,
        path.join(lockDirHome, ".dotfiles-lifecycle.lock"),
      );
      result = fixture.runDotfiles(lockDirHome, ["uninstall", "--apply"]);
      assert.equal(result.status, 1);
      assert.equal(text(path.join(lockDirTarget, "pid")), "99999999\n");

      const modeHome = path.join(fixture.root, "mode-home");
      mkdirSync(modeHome);
      chmodSync(modeHome, 0o755);
      result = fixture.runDotfiles(modeHome, ["uninstall", "--apply"]);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(mode(modeHome), 0o755);

      const relativeHome = path.join(fixture.root, "relative-home");
      mkdirSync(relativeHome);
      result = run(
        path.join(repositoryRoot, "bin/dotfiles"),
        ["uninstall", "--apply"],
        {
          cwd: fixture.root,
          env: {
            ...process.env,
            HOME: "relative-home",
            XDG_CONFIG_HOME: path.join(relativeHome, ".config"),
            XDG_STATE_HOME: path.join(relativeHome, ".state"),
            PATH: `${fixture.fakeBin}:/usr/bin:/bin`,
            DOTFILES: repositoryRoot,
          },
        },
      );
      assert.equal(result.status, 1);
      assert.equal(existsSync(path.join(relativeHome, ".local")), false);
    });
  });

  describe("uninstall", () => {
    it("removes only managed links and works with minimal commands", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.createConvergedHome("home");
      const gitconfig = path.join(home, ".gitconfig");
      rmSync(gitconfig);
      writeFileSync(gitconfig, "original local git config\n");
      let result = fixture.runDotfiles(home, ["install", "--force", "--apply"]);
      assert.equal(result.status, 0, result.stderr);
      const oldState = path.join(home, ".local/state/dotfiles/resources.tsv");
      mkdirSync(path.dirname(oldState), { recursive: true });
      writeFileSync(oldState, "legacy state remains untouched\n");
      rmSync(gitconfig);
      writeFileSync(gitconfig, "user replacement\n");
      const dry = fixture.runDotfiles(home, ["uninstall", "--dry-run"]);
      const apply = fixture.runDotfiles(home, ["uninstall", "--apply"]);
      // driftしたファイル、backup、package、旧stateはuninstallの対象外。
      assert.equal(dry.status, 0, dry.stderr);
      assert.equal(apply.status, 0, apply.stderr);
      assert.deepEqual(plans(apply.stdout), plans(dry.stdout));
      for (const name of [
        ".bashrc",
        ".bash_profile",
        ".config/mise/config.toml",
      ]) {
        assert.equal(existsSync(path.join(home, name)), false, name);
      }
      assert.equal(text(gitconfig), "user replacement\n");
      assert.equal(text(oldState), "legacy state remains untouched\n");
      assert.equal(existsSync(path.join(home, ".fake-brew-installed")), true);
      assert.equal(
        existsSync(path.join(home, "mise-data/tools-installed")),
        true,
      );
      assert.equal(backups(home, ".gitconfig").length, 1);

      const minimalBin = path.join(fixture.root, "minimal-bin");
      mkdirSync(minimalBin);
      for (const command of ["bash", "mkdir", "readlink", "rm", "rmdir"]) {
        const resolved = run("bash", [
          "-c",
          `command -v ${command}`,
        ]).stdout.trim();
        symlinkSync(resolved, path.join(minimalBin, command));
      }
      const minimalHome = path.join(fixture.root, "minimal-home");
      mkdirSync(minimalHome);
      symlinkSync(
        path.join(repositoryRoot, ".bashrc"),
        path.join(minimalHome, ".bashrc"),
      );
      result = run(
        path.join(repositoryRoot, "bin/dotfiles"),
        ["uninstall", "--apply"],
        {
          env: {
            ...process.env,
            HOME: minimalHome,
            XDG_CONFIG_HOME: path.join(minimalHome, ".config"),
            XDG_STATE_HOME: path.join(minimalHome, ".state"),
            PATH: minimalBin,
            DOTFILES: repositoryRoot,
          },
        },
      );
      // 復旧用途を想定し、Git・mise・HomebrewがないPATHでも削除できる。
      assert.equal(result.status, 0, result.stderr);
      assert.equal(existsSync(path.join(minimalHome, ".bashrc")), false);
    });
  });
});

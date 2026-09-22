import assert from "node:assert/strict";
import {
  chmodSync,
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";

import { repositoryRoot, run } from "./process.js";

const sanitizedEnvironmentKeys = new Set([
  "MISE_CONFIG_DIR",
  "MISE_SYSTEM_CONFIG_DIR",
  "MISE_ENV",
  "MISE_GLOBAL_CONFIG_FILE",
  "MISE_INSTALL_PATH",
  "DOTFILES_MISE_BOOTSTRAP_TARGET",
  "HOME",
  "XDG_CONFIG_HOME",
  "XDG_STATE_HOME",
  "MISE_DATA_DIR",
  "MISE_CACHE_DIR",
  "MISE_STATE_DIR",
  "MISE_NODE_VERSION",
  "DOTFILES_SKIP_BREW",
  "GITHUB_ACTIONS",
  "PATH",
  "DOTFILES",
  "TEST_PATH_PREFIX",
  "CREATE_DESTINATION_DURING_PREFLIGHT",
  "STREAM_MARKER",
  "STREAM_RELEASE_FILE",
]);

const sanitizedEnvironmentPrefixes = ["FAIL_", "FAKE_"];

/** テストごとに隔離したHOMEとfake commandを管理する。 */
export class TestFixture {
  constructor(t) {
    this.root = mkdtempSync(path.join(os.tmpdir(), "dotfiles-test."));
    this.fakeBin = path.join(this.root, "bin");
    mkdirSync(this.fakeBin);
    for (const command of ["mise", "brew"]) {
      const source = path.join(
        repositoryRoot,
        "tests/fixtures",
        `fake-${command}.bash`,
      );
      const target = path.join(this.fakeBin, command);
      copyFileSync(source, target);
      chmodSync(target, 0o755);
    }
    t.after(() => rmSync(this.root, { recursive: true, force: true }));
  }

  newHome(name) {
    const home = path.join(this.root, name);
    for (const directory of ["mise-data", "mise-cache", "mise-state"]) {
      mkdirSync(path.join(home, directory), { recursive: true });
    }
    return home;
  }

  runDotfiles(home, args, env = {}, options = {}) {
    // 呼び出し元のmise設定を持ち込まず、テスト専用HOMEだけを操作させる。
    return run(path.join(repositoryRoot, "bin/dotfiles"), args, {
      env: this.dotfilesEnv(home, env),
      ...options,
    });
  }

  dotfilesEnv(home, env = {}) {
    const inheritedEnvironment = Object.fromEntries(
      Object.entries(process.env).filter(
        ([key]) =>
          !sanitizedEnvironmentKeys.has(key) &&
          !sanitizedEnvironmentPrefixes.some((prefix) =>
            key.startsWith(prefix),
          ),
      ),
    );
    const caseEnvironment = { ...env };
    delete caseEnvironment.TEST_PATH_PREFIX;

    return {
      ...inheritedEnvironment,
      HOME: home,
      XDG_CONFIG_HOME: path.join(home, ".config"),
      XDG_STATE_HOME: path.join(home, ".local/state"),
      MISE_DATA_DIR: path.join(home, "mise-data"),
      MISE_CACHE_DIR: path.join(home, "mise-cache"),
      MISE_STATE_DIR: path.join(home, "mise-state"),
      MISE_NODE_VERSION: "ambient-must-not-leak",
      DOTFILES_SKIP_BREW: "0",
      GITHUB_ACTIONS: "false",
      PATH: `${env.TEST_PATH_PREFIX ? `${env.TEST_PATH_PREFIX}:` : ""}${this.fakeBin}:/usr/bin:/bin`,
      DOTFILES: repositoryRoot,
      ...caseEnvironment,
    };
  }

  createConvergedHome(name) {
    const home = this.newHome(name);
    const result = this.runDotfiles(home, ["install", "--apply"]);
    assert.equal(result.status, 0, result.stderr);
    return home;
  }
}

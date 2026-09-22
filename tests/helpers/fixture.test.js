import assert from "node:assert/strict";
import path from "node:path";
import { describe, it } from "node:test";

import { TestFixture } from "./fixture.js";

describe("TestFixture.dotfilesEnv", () => {
  it("removes ambient exact and prefixed variables before applying case overrides", (t) => {
    const fixture = new TestFixture(t);
    const home = fixture.newHome("home");
    const originalEnvironment = { ...process.env };

    Object.assign(process.env, {
      MISE_CONFIG_DIR: "/ambient/config",
      MISE_SYSTEM_CONFIG_DIR: "/ambient/system-config",
      MISE_ENV: "ambient",
      MISE_GLOBAL_CONFIG_FILE: "/ambient/global-config.toml",
      MISE_INSTALL_PATH: "/ambient/bin/mise",
      DOTFILES_MISE_BOOTSTRAP_TARGET: "/ambient/bootstrap/mise",
      FAIL_MISE_CONFIG: "1",
      FAIL_CURL: "1",
      FAKE_COMMAND_OUTPUT: "ambient output",
      TEST_PATH_PREFIX: "/ambient/bin",
      STREAM_MARKER: "/ambient/marker",
      FIXTURE_UNRELATED_VARIABLE: "preserved",
    });

    t.after(() => {
      for (const key of Object.keys(process.env)) {
        if (!(key in originalEnvironment)) delete process.env[key];
      }
      Object.assign(process.env, originalEnvironment);
    });

    const env = fixture.dotfilesEnv(home, {
      MISE_CONFIG_DIR: "/case/config",
      FAIL_MISE_CONFIG: "case",
      TEST_PATH_PREFIX: "/case/bin",
    });

    assert.equal(env.MISE_CONFIG_DIR, "/case/config");
    assert.equal(env.FAIL_MISE_CONFIG, "case");
    assert.equal(env.MISE_SYSTEM_CONFIG_DIR, undefined);
    assert.equal(env.MISE_ENV, undefined);
    assert.equal(env.MISE_GLOBAL_CONFIG_FILE, undefined);
    assert.equal(env.MISE_INSTALL_PATH, undefined);
    assert.equal(env.DOTFILES_MISE_BOOTSTRAP_TARGET, undefined);
    assert.equal(env.FAIL_CURL, undefined);
    assert.equal(env.FAKE_COMMAND_OUTPUT, undefined);
    assert.equal(env.STREAM_MARKER, undefined);
    assert.equal(env.FIXTURE_UNRELATED_VARIABLE, "preserved");
    assert.equal("TEST_PATH_PREFIX" in env, false);
    assert.equal(env.PATH, `/case/bin:${fixture.fakeBin}:/usr/bin:/bin`);
    assert.equal(env.HOME, home);
    assert.equal(env.XDG_CONFIG_HOME, path.join(home, ".config"));
  });
});

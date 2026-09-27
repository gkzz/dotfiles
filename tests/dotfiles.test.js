import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it } from "node:test";

import { repositoryRoot, run } from "./helpers/process.js";

describe("mise dotfiles boundary", () => {
  it("encodes generated TOML strings and produces a parseable config", () => {
    const root = mkdtempSync(path.join(os.tmpdir(), "dotfiles-config-test."));
    try {
      const config = path.join(root, "generated.toml");
      const result = run("bash", [
        "-c",
        `
          set -euo pipefail
          DOTFILES=$1
          HOME=$2
          . "$DOTFILES/setup/dotfiles.bash"
          write_dotfiles_config "$3" "$DOTFILES" "$HOME/.dotfiles" \
            "$DOTFILES/mise.toml" "$HOME/config with \\"quote\\"/mise/config.toml" true
        `,
        "_",
        repositoryRoot,
        root,
        config,
      ]);
      assert.equal(result.status, 0, result.stderr);
      assert.match(readFileSync(config, "utf8"), /\\"quote\\"/);

      const parsed = run("mise", ["--cd", root, "config", "--json"], {
        env: {
          ...process.env,
          MISE_GLOBAL_CONFIG_FILE: config,
          MISE_OVERRIDE_CONFIG_FILENAMES: ".dotfiles-no-project.toml",
          MISE_NO_ENV: "1",
          MISE_NO_HOOKS: "1",
        },
      });
      assert.equal(parsed.status, 0, parsed.stderr);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("gates verify dotfiles checks on dirname availability", () => {
    const result = run("bash", [
      "-c",
      `
        set -euo pipefail
        . "$1/setup/lib.bash"
        have_cmd() { [ "$1" != dirname ]; }
        CHECK_FAILED=false
        validate_verify_commands
        test "$CHECK_HAVE_DIRNAME" = false
        test "$CHECK_FAILED" = true
      `,
      "_",
      repositoryRoot,
    ]);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /required command is missing: dirname/);
  });
});

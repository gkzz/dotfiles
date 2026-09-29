import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it } from "node:test";

import { repositoryRoot, run } from "./helpers/process.js";

describe("mise Dotfilesとの境界", () => {
  it("特殊文字を符号化し、実miseで読み込めるTOMLを生成する", () => {
    const root = mkdtempSync(path.join(os.tmpdir(), "dotfiles-config-test."));
    try {
      const config = path.join(root, "generated.toml");
      const configTarget = path.join(
        root,
        'config with "quote"',
        "backslash\\\\segment",
        "mise/config.toml",
      );
      const result = run("bash", [
        "-c",
        `
          set -euo pipefail
          DOTFILES=$1
          HOME=$2
          . "$DOTFILES/setup/dotfiles.bash"
          write_dotfiles_config "$3" "$DOTFILES" "$HOME/.dotfiles" \
            "$DOTFILES/mise.toml" "$4" true
        `,
        "_",
        repositoryRoot,
        root,
        config,
        configTarget,
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
});

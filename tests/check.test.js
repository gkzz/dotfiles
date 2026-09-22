import assert from "node:assert/strict";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readlinkSync,
  rmSync,
  symlinkSync,
} from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";

import { TestFixture } from "./helpers/fixture.js";
import { repositoryRoot, run } from "./helpers/process.js";

describe("verify prerequisites", () => {
  it("reports an unreadable repository input once and skips dependent checks", (t) => {
    const fixture = new TestFixture(t);
    const repository = path.join(fixture.root, "repository");
    cpSync(repositoryRoot, repository, {
      recursive: true,
      filter: (source) => {
        const gitDirectory = path.join(repositoryRoot, ".git");
        return (
          source !== gitDirectory &&
          !source.startsWith(`${gitDirectory}${path.sep}`)
        );
      },
    });
    assert.equal(existsSync(path.join(repository, ".git")), false);
    const config = path.join(repository, ".config/mise/config.toml");
    rmSync(config);
    const home = fixture.newHome("home");
    const destination = path.join(home, ".config/mise/config.toml");
    mkdirSync(path.dirname(destination), { recursive: true });
    symlinkSync(config, destination);

    const result = run(path.join(repository, "bin/dotfiles"), ["verify"], {
      env: fixture.dotfilesEnv(home, {
        DOTFILES: repository,
        DOTFILES_SKIP_BREW: "1",
      }),
    });

    assert.equal(result.status, 1, result.stderr);
    const diagnostic = `required repository file is not readable: ${config}`;
    assert.equal(result.stderr.split(diagnostic).length - 1, 1);
    assert.doesNotMatch(result.stderr, /managed symlink source is missing/);
    assert.doesNotMatch(result.stderr, /failed to copy mise config/);
    assert.doesNotMatch(result.stderr, /mise could not inspect tools/);
    assert.equal(readlinkSync(destination), config);
  });

  it("does not run a validator when its required command is missing", () => {
    const script = `
      . "$LIB_FILE"
      CHECK_FAILED=false; DOTFILES="$REPOSITORY"
      MISE_CONFIG_SOURCE="$REPOSITORY/.config/mise/config.toml"
      MISE_LOCK_SOURCE="$REPOSITORY/.config/mise/mise.lock"
      have_cmd() { [ "$1" != git ]; }
      git() { printf "%s\\n" "git validator unexpectedly ran"; return 1; }
      validate_verify_commands; validate_repository
      [ "$CHECK_FAILED" = true ]
    `;
    const result = run("bash", ["-c", script], {
      env: {
        ...process.env,
        LIB_FILE: path.join(repositoryRoot, "setup/lib.bash"),
        REPOSITORY: repositoryRoot,
      },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(
      result.stderr,
      /verify error: required command is missing: git/,
    );
    assert.doesNotMatch(result.stdout, /git validator unexpectedly ran/);
    assert.doesNotMatch(result.stderr, /Git configuration syntax is invalid/);
  });
});

import assert from "node:assert/strict";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";

import { TestFixture } from "./helpers/fixture.js";
import { repositoryRoot, run } from "./helpers/process.js";
import { repositoryConfig } from "./helpers/repository-config.js";

const executable = (file, contents) => {
  writeFileSync(file, contents);
  chmodSync(file, 0o755);
};

describe("bootstrap", () => {
  it("ignores ambient mise overrides and uses the pinned release", (t) => {
    const fixture = new TestFixture(t);
    const home = fixture.newHome("home");
    const installer = path.join(repositoryRoot, "setup/mise-install.sh");
    const result = run(installer, ["--dry-run"], {
      env: fixture.dotfilesEnv(home, {
        MISE_VERSION: "v0.0.0",
        MISE_INSTALL_PATH: "/tmp/unmanaged-mise",
      }),
    });
    assert.equal(result.status, 0, result.stderr);
    assert.ok(
      result.stdout.includes(
        `MISE_VERSION=${repositoryConfig.miseMinimumVersion}`,
      ),
    );
    assert.ok(
      result.stdout.includes(
        `MISE_INSTALL_PATH=${path.join(home, ".local/bin/mise")}`,
      ),
    );
    const source = readFileSync(installer, "utf8");
    assert.match(source, /github\.com\/jdx\/mise\/releases\/download/);
    assert.match(source, /sha256sum -c -/);
  });

  it("downloads the official Homebrew installer and propagates download and execution failures", async (t) => {
    const fixture = new TestFixture(t);
    const home = fixture.newHome("home");
    const bin = path.join(fixture.root, "curl-bin");
    mkdirSync(bin);
    executable(
      path.join(bin, "curl"),
      `#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\\n' "$*" >> "$HOME/homebrew-calls"
[ "\${FAIL_CURL:-0}" != 1 ] || exit 1
printf '%s\\n' '[ "\${FAIL_INSTALLER:-0}" != 1 ] || exit 1' 'touch "$HOME/homebrew-installer-ran"'
`,
    );
    const installer = path.join(repositoryRoot, "setup/homebrew-install.sh");
    const execute = (env = {}) =>
      run(installer, ["--apply"], {
        env: {
          ...fixture.dotfilesEnv(home),
          PATH: `${bin}:/usr/bin:/bin`,
          ...env,
        },
      });
    await t.test("success", () => {
      const result = execute();
      assert.equal(result.status, 0, result.stderr);
      assert.match(
        readFileSync(path.join(home, "homebrew-calls"), "utf8"),
        /Homebrew\/install\/HEAD\/install\.sh/,
      );
      assert.equal(
        readFileSync(path.join(home, "homebrew-installer-ran"), "utf8"),
        "",
      );
    });
    await t.test("download failure", () =>
      assert.notEqual(execute({ FAIL_CURL: "1" }).status, 0),
    );
    await t.test("installer failure", () =>
      assert.notEqual(execute({ FAIL_INSTALLER: "1" }).status, 0),
    );
  });

  it("evaluates shellenv from the brew discovered after bootstrap", (t) => {
    const fixture = new TestFixture(t);
    const home = fixture.newHome("home");
    const repository = path.join(fixture.root, "repository");
    const bin = path.join(fixture.root, "bin2");
    mkdirSync(path.join(repository, "setup"), { recursive: true });
    mkdirSync(bin);
    executable(
      path.join(repository, "setup/homebrew-install.sh"),
      '#!/usr/bin/env bash\nprintf "installer %s\\n" "$*" >> "$HOME/calls"\n',
    );
    executable(
      path.join(bin, "brew"),
      '#!/usr/bin/env bash\nprintf "brew %s\\n" "$*" >> "$HOME/calls"\n[ "$1" = shellenv ] && printf "%s\\n" "export HOMEBREW_HANDOFF_COMPLETE=1"\n',
    );
    const result = run(
      "bash",
      [
        "-c",
        '. "$LIB_FILE"; . "$PACKAGES_FILE"; DOTFILES="$TEST_DOTFILES"; bootstrap_homebrew_action; [ "$HOMEBREW_HANDOFF_COMPLETE" = 1 ]',
      ],
      {
        env: {
          ...fixture.dotfilesEnv(home),
          PATH: `${bin}:/usr/bin:/bin`,
          TEST_DOTFILES: repository,
          LIB_FILE: path.join(repositoryRoot, "setup/lib.bash"),
          PACKAGES_FILE: path.join(repositoryRoot, "setup/packages.bash"),
        },
      },
    );
    assert.equal(result.status, 0, result.stderr);
    const calls = readFileSync(path.join(home, "calls"), "utf8");
    assert.match(calls, /installer --apply/);
    assert.match(calls, /brew shellenv/);
  });

  it("uses a temporary mise only for lockfile validation", async (t) => {
    const fixture = new TestFixture(t);
    const repository = path.join(fixture.root, "repository");
    mkdirSync(path.join(repository, "setup"), { recursive: true });
    writeFileSync(path.join(repository, "config.toml"), "[tools]\n");
    writeFileSync(path.join(repository, "mise.lock"), "[tools]\n");
    executable(
      path.join(repository, "setup/mise-install.sh"),
      `#!/usr/bin/env bash
cat > "$DOTFILES_MISE_BOOTSTRAP_TARGET" <<'MISE'
#!/usr/bin/env bash
[ "\${1:-}" != --cd ] || shift 2
case "\${1:-}" in config) printf '%s\\n' '{}';; install) [ "\${FAIL_LOCK_VALIDATION:-0}" != 1 ];; *) exit 1;; esac
MISE
chmod +x "$DOTFILES_MISE_BOOTSTRAP_TARGET"
`,
    );
    const script =
      '. "$LIB_FILE"; . "$PACKAGES_FILE"; PREFLIGHT_FAILED=false; MISE_CMD=; validate_mise_with_temporary_bootstrap; [ "$PREFLIGHT_FAILED" = false ] && [ -z "$MISE_CMD" ]';
    const execute = (env = {}) =>
      run("bash", ["-c", script], {
        env: {
          ...process.env,
          DOTFILES: repository,
          MISE_CONFIG_SOURCE: path.join(repository, "config.toml"),
          MISE_LOCK_SOURCE: path.join(repository, "mise.lock"),
          LIB_FILE: path.join(repositoryRoot, "setup/lib.bash"),
          PACKAGES_FILE: path.join(repositoryRoot, "setup/packages.bash"),
          ...env,
        },
      });
    await t.test("valid lockfile", () => assert.equal(execute().status, 0));
    await t.test("invalid lockfile", () =>
      assert.notEqual(execute({ FAIL_LOCK_VALIDATION: "1" }).status, 0),
    );
  });

  it("passes the composite action install path through the explicit bootstrap boundary", (t) => {
    const fixture = new TestFixture(t);
    const home = fixture.newHome("home");
    const target = path.join(fixture.root, "action-bin/mise");
    const result = run(
      path.join(repositoryRoot, "setup/mise-install.sh"),
      ["--dry-run"],
      {
        env: fixture.dotfilesEnv(home, {
          DOTFILES_MISE_BOOTSTRAP_TARGET: target,
          MISE_INSTALL_PATH: "/tmp/ambient-mise",
        }),
      },
    );
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.stdout.includes(`MISE_INSTALL_PATH=${target}`));
    const action = readFileSync(
      path.join(repositoryRoot, ".github/actions/setup-mise/action.yml"),
      "utf8",
    );
    for (const expression of [
      'DOTFILES_MISE_BOOTSTRAP_TARGET="$MISE_INSTALL_PATH"',
      "$GITHUB_ACTION_PATH/../../../setup/mise-version.sh",
      "$GITHUB_ACTION_PATH/../../../setup/mise-install.sh",
      "mise install --locked --yes",
    ])
      assert.ok(action.includes(expression), expression);
  });

  it("rejects a non-executable bootstrap target without changing it", (t) => {
    const fixture = new TestFixture(t);
    const home = fixture.newHome("home");
    const target = path.join(home, ".local/bin/mise");
    mkdirSync(path.dirname(target), { recursive: true });
    writeFileSync(target, "unmanaged binary\n");
    const result = fixture.runDotfiles(
      home,
      ["install", "--skip-brew", "--dry-run"],
      { PATH: "/usr/bin:/bin" },
    );
    assert.notEqual(result.status, 0);
    assert.equal(readFileSync(target, "utf8"), "unmanaged binary\n");
  });
});

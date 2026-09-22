import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it } from "node:test";

import { TestFixture } from "./helpers/fixture.js";
import { repositoryRoot, run } from "./helpers/process.js";
import { repositoryConfig } from "./helpers/repository-config.js";

/**
 * Homebrewとmiseの検査・適用境界を検証する。
 * miseのresult state、apply時のstreaming、checkの診断、--skip-brewが対象。
 */
const configSource = path.join(repositoryRoot, ".config/mise/config.toml");
const lockSource = path.join(repositoryRoot, ".config/mise/mise.lock");
const packageEnv = {
  ...process.env,
  LIB_FILE: path.join(repositoryRoot, "setup/lib.bash"),
  PACKAGES_FILE: path.join(repositoryRoot, "setup/packages.bash"),
  CONFIG_SOURCE: configSource,
  LOCK_SOURCE: lockSource,
};

function runState(faults = "") {
  const script = `
    . "$LIB_FILE"; . "$PACKAGES_FILE"
    MISE_CONFIG_SOURCE="$CONFIG_SOURCE"; MISE_LOCK_SOURCE="$LOCK_SOURCE"
    fake_mise() { printf "%s\\n" "captured stdout"; printf "%s\\n" "captured stderr" >&2; return "\${FAKE_MISE_STATUS:-0}"; }
  MISE_CMD=fake_mise
    ${faults}
  set +e; run_repository_mise_capture config --json; operation_status=$?; set -e
    printf "operation_status=%s\\nstage=%s\\nreason=%s\\nstatus=%s\\nstdout=%s\\nstderr=%s\\ncleanup_status=%s\\ncleanup_stderr=%s\\ntemp_exists=%s\\n" \\
    "$operation_status" "$REPOSITORY_MISE_RESULT_STAGE" "$REPOSITORY_MISE_RESULT_REASON" \\
    "$REPOSITORY_MISE_RESULT_STATUS" "$REPOSITORY_MISE_RESULT_STDOUT" "$REPOSITORY_MISE_RESULT_STDERR" \\
    "$REPOSITORY_MISE_RESULT_CLEANUP_STATUS" "$REPOSITORY_MISE_RESULT_CLEANUP_STDERR" \\
    "$([ -e "$REPOSITORY_MISE_RESULT_TEMP_PATH" ] && printf yes || printf no)"
    `;
  const result = run("bash", ["-c", script], { env: packageEnv });
  assert.equal(result.status, 0, result.stderr);
  return Object.fromEntries(
    result.stdout
      .trim()
      .split("\n")
      .map((line) => line.split(/=(.*)/s).slice(0, 2)),
  );
}

describe("package lifecycle", () => {
  describe("repository mise execution", () => {
    it("preserves primary and cleanup outcomes in result state", () => {
      assert.deepEqual(runState(), {
        operation_status: "0",
        stage: "",
        reason: "",
        status: "0",
        stdout: "captured stdout",
        stderr: "captured stderr",
        cleanup_status: "0",
        cleanup_stderr: "",
        temp_exists: "no",
      });
      assert.deepEqual(
        runState(`
                FAKE_MISE_STATUS=37; export FAKE_MISE_STATUS
                `),
        {
          operation_status: "37",
          stage: "mise",
          reason: "mise",
          status: "37",
          stdout: "captured stdout",
          stderr: "captured stderr",
          cleanup_status: "0",
          cleanup_stderr: "",
          temp_exists: "no",
        },
      );
      assert.deepEqual(
        runState(`
                rm() { command rm "$@"; printf "%s\\n" "captured cleanup stderr" >&2; return 21; }
                `),
        {
          operation_status: "1",
          stage: "cleanup",
          reason: "cleanup",
          status: "0",
          stdout: "captured stdout",
          stderr: "captured stderr",
          cleanup_status: "21",
          cleanup_stderr: "captured cleanup stderr",
          temp_exists: "no",
        },
      );
      assert.deepEqual(
        runState(`
                rm() { command rm "$@"; printf "%s\\n" "captured cleanup stderr" >&2; return 21; }
                FAKE_MISE_STATUS=37; export FAKE_MISE_STATUS
                `),
        {
          operation_status: "37",
          stage: "mise",
          reason: "mise",
          status: "37",
          stdout: "captured stdout",
          stderr: "captured stderr",
          cleanup_status: "21",
          cleanup_stderr: "captured cleanup stderr",
          temp_exists: "no",
        },
      );
      assert.deepEqual(
        runState(`
      mkdir() { printf "%s\\n" "captured prepare stderr" >&2; return 22; }
      `),
        {
          operation_status: "1",
          stage: "prepare",
          reason: "mkdir",
          status: "",
          stdout: "",
          stderr: "captured prepare stderr",
          cleanup_status: "0",
          cleanup_stderr: "",
          temp_exists: "no",
        },
      );
      assert.deepEqual(
        runState(`
      mkdir() { printf "%s\\n" "captured prepare stderr" >&2; return 22; }
      rm() { command rm "$@"; printf "%s\\n" "captured cleanup stderr" >&2; return 23; }
      `),
        {
          operation_status: "1",
          stage: "prepare",
          reason: "mkdir",
          status: "",
          stdout: "",
          stderr: "captured prepare stderr",
          cleanup_status: "23",
          cleanup_stderr: "captured cleanup stderr",
          temp_exists: "no",
        },
      );
    });

    it("rejects an unknown I/O mode with exit code 2", () => {
      const result = run("bash", [
        "-c",
        '. "$1/setup/lib.bash"; . "$1/setup/packages.bash"; run_repository_mise_with_io typo config --json',
        "_",
        repositoryRoot,
      ]);
      assert.equal(result.status, 2);
    });
  });

  describe("install", () => {
    it("streams mise output before the process exits", async (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.newHome("stream-home");
      const release = path.join(fixture.root, "stream.release");
      const marker = "fake mise streaming marker";
      let output = "";
      const child = spawn(
        path.join(repositoryRoot, "bin/dotfiles"),
        ["install", "--skip-brew", "--apply"],
        {
          env: fixture.dotfilesEnv(home, {
            STREAM_MARKER: marker,
            STREAM_RELEASE_FILE: release,
          }),
        },
      );
      child.stdout.setEncoding("utf8");
      child.stderr.setEncoding("utf8");
      child.stdout.on("data", (chunk) => {
        output += chunk;
      });
      child.stderr.on("data", (chunk) => {
        output += chunk;
      });
      t.after(() => {
        if (child.exitCode === null) child.kill();
      });
      const deadline = Date.now() + 5000;
      while (!output.includes(marker) && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      // release前にmarkerが見えれば、applyの出力は完了までbufferされていない。
      assert.match(output, new RegExp(marker));
      writeFileSync(release, "");
      assert.equal(
        await new Promise((resolve) => child.once("close", resolve)),
        0,
        output,
      );
    });

    it("reports mise preparation failures without verify prefixes", () => {
      const installFailure = run(
        "bash",
        [
          "-c",
          `
        . "$LIB_FILE"; . "$PACKAGES_FILE"
        MISE_CMD=/bin/true; MISE_CONFIG_SOURCE="$CONFIG_SOURCE"; MISE_LOCK_SOURCE="$LOCK_SOURCE"
        mktemp() { printf "%s\\n" "fake install mktemp failure" >&2; return 1; }
        apply_mise_tools
        `,
        ],
        { env: packageEnv },
      );
      assert.equal(installFailure.status, 1, installFailure.stderr);
      assert.match(
        installFailure.stderr,
        /failed to create temporary directory for mise inspection/,
      );
      assert.doesNotMatch(installFailure.stderr, /verify error:/);
    });

    it("omits every Homebrew inspection and action with --skip-brew", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.newHome("skip-home");
      const result = fixture.runDotfiles(home, [
        "install",
        "--skip-brew",
        "--apply",
      ]);
      assert.equal(result.status, 0, result.stderr);
      assert.doesNotMatch(
        readFileSync(path.join(home, "calls"), "utf8"),
        /brew /,
      );
    });
  });

  describe("verify", () => {
    it("classifies mise preparation and cleanup failures", async (t) => {
      const cases = [
        [
          "mktemp",
          'mktemp() { printf "%s\\n" "fake mktemp failure" >&2; return 1; }',
          /failed to create temporary directory for mise inspection/,
        ],
        [
          "mkdir",
          'mkdir() { printf "%s\\n" "fake mkdir failure" >&2; return 1; }',
          /failed to create temporary mise system directory/,
        ],
        [
          "config copy",
          'cp() { [ "$1" != "$MISE_CONFIG_SOURCE" ] || { printf "%s\\n" "fake cp failure" >&2; return 1; }; command cp "$@"; }',
          /failed to copy mise config into temporary directory/,
        ],
        [
          "lock copy",
          'cp() { [ "$1" != "$MISE_LOCK_SOURCE" ] || { printf "%s\\n" "fake cp failure" >&2; return 1; }; command cp "$@"; }',
          /failed to copy mise lockfile into temporary directory/,
        ],
        [
          "cleanup",
          'rm() { command rm "$@"; printf "%s\\n" "fake cleanup failure" >&2; return 1; }',
          /failed to remove temporary mise directory/,
        ],
      ];
      for (const [name, fault, diagnostic] of cases) {
        await t.test(name, (t) => {
          const script = `
            . "$LIB_FILE"; . "$PACKAGES_FILE"
            CHECK_FAILED=false; MISE_CMD=/bin/true
            MISE_CONFIG_SOURCE="$CONFIG_SOURCE"; MISE_LOCK_SOURCE="$LOCK_SOURCE"
            ${fault}
            check_mise_tools
            [ "$CHECK_FAILED" = true ]
          `;
          const result = run("bash", ["-c", script], { env: packageEnv });
          assert.equal(result.status, 0, result.stderr);
          assert.match(result.stderr, diagnostic);
          if (name === "cleanup") {
            const fixture = new TestFixture(t);
            const home = fixture.createConvergedHome("home");
            const failureBin = path.join(fixture.root, "failure-bin");
            const fakeRm = path.join(failureBin, "rm");
            mkdirSync(failureBin);
            writeFileSync(
              fakeRm,
              `#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *dotfiles-mise.*) printf '%s\\n' 'fake cleanup failure' >&2; exit 21 ;;
esac
exec /bin/rm "$@"
`,
            );
            chmodSync(fakeRm, 0o755);
            const cliResult = fixture.runDotfiles(
              home,
              ["verify", "--skip-brew"],
              { TEST_PATH_PREFIX: failureBin },
            );
            assert.equal(cliResult.status, 1, cliResult.stderr);
            assert.match(cliResult.stderr, diagnostic);
            assert.match(cliResult.stderr, /fake cleanup failure/);
            assert.doesNotMatch(cliResult.stdout, /verify complete/);
            const temporaryPath = cliResult.stderr.match(
              /failed to remove temporary mise directory: path=(.+)/,
            )?.[1];
            assert.ok(
              temporaryPath,
              "cleanup diagnostic must include its path",
            );
            assert.equal(
              path.resolve(path.dirname(temporaryPath)),
              path.resolve(os.tmpdir()),
            );
            assert.match(path.basename(temporaryPath), /^dotfiles-mise\./);
            rmSync(temporaryPath, { recursive: true, force: true });
          }
        });
      }
    });

    it("preserves primary mise failures and also reports cleanup failures", async (t) => {
      for (const primary of ["prepare", "mise"]) {
        await t.test(`${primary} + cleanup`, () => {
          const prepareFault =
            primary === "prepare"
              ? 'mkdir() { printf "%s\\n" "fake combined mkdir failure" >&2; return 1; }'
              : "";
          const script = `
            . "$LIB_FILE"; . "$PACKAGES_FILE"
            CHECK_FAILED=false
            fake_combined_mise() { return 37; }; MISE_CMD=fake_combined_mise
            MISE_CONFIG_SOURCE="$CONFIG_SOURCE"; MISE_LOCK_SOURCE="$LOCK_SOURCE"
            ${prepareFault}
            rm() { command rm "$@"; printf "%s\\n" "fake combined cleanup failure" >&2; return 1; }
            set +e; run_repository_mise_capture config --json; primary_status=$?; set -e
            report_repository_mise_verify_error "mise could not load the isolated repository config"
            [ "$primary_status" -eq ${primary === "prepare" ? 1 : 37} ]
            [ "$REPOSITORY_MISE_RESULT_CLEANUP_STATUS" -ne 0 ]
            [ "$CHECK_FAILED" = true ]
          `;
          const result = run("bash", ["-c", script], { env: packageEnv });
          assert.equal(result.status, 0, result.stderr);
          assert.match(
            result.stderr,
            /failed to remove temporary mise directory/,
          );
          assert.match(result.stderr, /fake combined cleanup failure/);
          assert.match(
            result.stderr,
            primary === "prepare"
              ? /failed to create temporary mise system directory/
              : /mise could not load the isolated repository config/,
          );
        });
      }
    });

    it("reports mise operation failures with original stderr", async (t) => {
      const cases = [
        [
          "config",
          { FAIL_MISE_CONFIG: "1" },
          /mise could not load the isolated repository config/,
          /fake mise config failure/,
        ],
        [
          "lock",
          { FAIL_MISE_LOCK: "1" },
          /mise could not validate the repository lockfile/,
          /fake mise lock failure/,
        ],
        [
          "ls",
          { FAIL_MISE_LS: "1" },
          /mise could not inspect tools/,
          /fake mise ls failure/,
        ],
        ...[90, 91, 92, 93, 94, 95].map((status) => [
          `status ${status}`,
          { FAIL_MISE_LS_STATUS: String(status) },
          /mise could not inspect tools/,
          new RegExp(`fake mise ls status ${status}`),
        ]),
      ];
      for (const [name, env, diagnostic, originalError] of cases) {
        await t.test(name, (t) => {
          const fixture = new TestFixture(t);
          const home = fixture.createConvergedHome("home");
          const result = fixture.runDotfiles(
            home,
            ["verify", "--skip-brew"],
            env,
          );
          assert.equal(result.status, 1, result.stderr);
          assert.match(result.stderr, diagnostic);
          assert.match(result.stderr, originalError);
          assert.doesNotMatch(result.stderr, /mise tools are missing/);
          assert.doesNotMatch(result.stderr, /failed to (create|copy|remove)/);
        });
      }
    });

    it("delegates package state to Homebrew and mise", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.createConvergedHome("home");
      const result = fixture.runDotfiles(home, ["verify"]);
      assert.equal(result.status, 0, result.stderr);
      const calls = readFileSync(path.join(home, "calls"), "utf8");
      assert.match(
        calls,
        new RegExp(
          `brew bundle check --no-upgrade --file ${repositoryRoot}/Brewfile`,
        ),
      );
      assert.match(calls, /mise ls --missing --no-header node-version=unset/);
    });

    it("reports missing mise tools without installing them", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.createConvergedHome("home");
      rmSync(path.join(home, "mise-data/tools-installed"));
      const result = fixture.runDotfiles(home, ["verify", "--skip-brew"]);
      assert.equal(result.status, 1);
      assert.match(result.stderr, /verify failed: mise tools are missing:/);
      assert.ok(
        result.stderr.includes(`node ${repositoryConfig.tools.node} missing`),
      );
      assert.equal(
        existsSync(path.join(home, "mise-data/tools-installed")),
        false,
      );
    });

    it("preserves successful mise warnings", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.createConvergedHome("home");
      writeFileSync(path.join(home, "mise-data/tools-installed"), "");
      const result = fixture.runDotfiles(home, ["verify", "--skip-brew"], {
        FAKE_MISE_LS_WARNING: "1",
      });
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stderr, /fake mise ls warning/);
      assert.match(result.stdout, /verify complete/);
      assert.doesNotMatch(result.stderr, /mise tools are missing/);
    });
  });
});

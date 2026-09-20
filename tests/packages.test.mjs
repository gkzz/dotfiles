import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";

import { TestFixture } from "./helpers/fixture.mjs";
import { repositoryRoot, run } from "./helpers/process.mjs";

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

    it("reports mise preparation failures without check prefixes", () => {
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
      assert.doesNotMatch(installFailure.stderr, /check error:/);
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

  describe("check", () => {
    it("delegates package state to Homebrew and mise", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.createConvergedHome("home");
      const result = fixture.runDotfiles(home, ["check"]);
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
      const result = fixture.runDotfiles(home, ["check", "--skip-brew"]);
      assert.equal(result.status, 1);
      assert.match(result.stderr, /check failed: mise tools are missing:/);
      assert.match(result.stderr, /node 24\.19\.0 missing/);
      assert.equal(
        existsSync(path.join(home, "mise-data/tools-installed")),
        false,
      );
    });

    it("preserves successful mise warnings", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.createConvergedHome("home");
      writeFileSync(path.join(home, "mise-data/tools-installed"), "");
      const result = fixture.runDotfiles(home, ["check", "--skip-brew"], {
        FAKE_MISE_LS_WARNING: "1",
      });
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stderr, /fake mise ls warning/);
      assert.match(result.stdout, /check complete/);
      assert.doesNotMatch(result.stderr, /mise tools are missing/);
    });
  });
});

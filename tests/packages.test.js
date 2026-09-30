import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";

import { TestFixture } from "./helpers/fixture.js";
import { repositoryRoot, run } from "./helpers/process.js";

const packageEnv = {
  ...process.env,
  LIB_FILE: path.join(repositoryRoot, "setup/lib.bash"),
  PACKAGES_FILE: path.join(repositoryRoot, "setup/packages.bash"),
  CONFIG_SOURCE: path.join(repositoryRoot, "mise.toml"),
  LOCK_SOURCE: path.join(repositoryRoot, "mise.lock"),
};

describe("パッケージのライフサイクル", () => {
  describe("install", () => {
    it("miseの処理中に出力を逐次表示する", async (t) => {
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
      assert.match(output, new RegExp(marker));
      writeFileSync(release, "");
      assert.equal(
        await new Promise((resolve) => child.once("close", resolve)),
        0,
        output,
      );
    });

    it("通常installでも一時設定のstateを隔離し、dataとcacheは維持する", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.newHome("state-home");
      const result = run(
        "bash",
        [
          "-c",
          `
        . "$LIB_FILE"; . "$PACKAGES_FILE"
        MISE_CONFIG_SOURCE="$CONFIG_SOURCE"; MISE_LOCK_SOURCE="$LOCK_SOURCE"
        fake_mise() {
          mkdir -p "$MISE_STATE_DIR" "$MISE_DATA_DIR" "$MISE_CACHE_DIR"
          printf tracked > "$MISE_STATE_DIR/tracked-config"
          printf installed > "$MISE_DATA_DIR/installed"
          printf cached > "$MISE_CACHE_DIR/download"
        }
        MISE_CMD=fake_mise
        run_repository_mise_apply install --locked --yes
      `,
        ],
        {
          env: {
            ...packageEnv,
            HOME: home,
            MISE_DATA_DIR: path.join(home, "data"),
            MISE_CACHE_DIR: path.join(home, "cache"),
            MISE_STATE_DIR: path.join(home, "state"),
          },
        },
      );
      assert.equal(result.status, 0, result.stderr);
      assert.equal(existsSync(path.join(home, "state")), false);
      assert.equal(
        readFileSync(path.join(home, "data/installed"), "utf8"),
        "installed",
      );
      assert.equal(
        readFileSync(path.join(home, "cache/download"), "utf8"),
        "cached",
      );
    });

    it("miseが失敗したときは終了状態とstderrを維持する", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.newHome("failure-home");
      const result = fixture.runDotfiles(
        home,
        ["install", "--skip-brew", "--apply"],
        { FAIL_MISE_INSTALL: "1" },
      );
      assert.equal(result.status, 23, result.stderr);
      assert.match(result.stderr, /fake mise install failure/);
    });

    it("miseの実行準備に失敗した理由をinstallの診断として表示する", () => {
      const result = run(
        "bash",
        [
          "-c",
          `. "$LIB_FILE"; . "$PACKAGES_FILE"
           MISE_CMD=/bin/true; MISE_CONFIG_SOURCE="$CONFIG_SOURCE"; MISE_LOCK_SOURCE="$LOCK_SOURCE"
           mktemp() { printf '%s\\n' 'fake mktemp failure' >&2; return 1; }
           apply_mise_tools`,
        ],
        { env: packageEnv },
      );
      assert.equal(result.status, 1, result.stderr);
      assert.match(result.stderr, /failed to create temporary directory/);
      assert.match(result.stderr, /fake mktemp failure/);
      assert.doesNotMatch(result.stderr, /verify error:/);
    });

    it("--skip-brew指定時はHomebrewを検査も適用もしない", (t) => {
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

  describe("一時ディレクトリの後始末", () => {
    it("準備または実行の失敗を優先し、cleanupの失敗も報告する", async (t) => {
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

    it("cleanupに失敗した場合は操作を失敗として診断する", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.newHome("cleanup-failure-home");
      const failingBin = fixture.createFailingMiseCleanupCommand();
      const result = fixture.runDotfiles(
        home,
        ["install", "--apply", "--skip-brew"],
        { TEST_PATH_PREFIX: failingBin },
      );
      assert.equal(result.status, 1, result.stderr);
      assert.match(
        result.stderr,
        /error: failed to remove temporary mise directory/,
      );
      assert.match(result.stderr, /fake cleanup failure/);
      assert.match(result.stderr, /install preflight failed/);
    });
  });

  describe("verify", () => {
    it("miseの代表的な失敗を元のstderrとともに報告する", async (t) => {
      const cases = [
        [
          "config",
          { FAIL_MISE_CONFIG: "1" },
          /could not load/,
          /config failure/,
        ],
        ["lock", { FAIL_MISE_LOCK: "1" }, /could not validate/, /lock failure/],
        [
          "ls",
          { FAIL_MISE_LS_STATUS: "37" },
          /could not inspect/,
          /ls status 37/,
        ],
      ];
      for (const [name, env, summary, original] of cases) {
        await t.test(name, (t) => {
          const fixture = new TestFixture(t);
          const home = fixture.createConvergedHome("home");
          const result = fixture.runDotfiles(
            home,
            ["verify", "--skip-brew"],
            env,
          );
          assert.equal(result.status, 1, result.stderr);
          assert.match(result.stderr, summary);
          assert.match(result.stderr, original);
          assert.doesNotMatch(result.stderr, /mise tools are missing/);
        });
      }
    });

    it("不足しているツールを報告するだけでinstallは実行しない", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.createConvergedHome("home");
      rmSync(path.join(home, "mise-data/tools-installed"));
      const callsBeforeVerify = fixture.markCalls(home);
      const result = fixture.runDotfiles(home, ["verify", "--skip-brew"]);
      assert.equal(result.status, 1);
      assert.match(result.stderr, /mise tools are missing:/);
      assert.match(result.stderr, /node missing/);
      assert.equal(
        existsSync(path.join(home, "mise-data/tools-installed")),
        false,
      );
      assert.doesNotMatch(
        fixture.readCalls(home, callsBeforeVerify),
        /mise install --locked --yes/,
      );
    });

    it("miseが成功時に出した警告を隠さない", (t) => {
      const fixture = new TestFixture(t);
      const home = fixture.createConvergedHome("home");
      const result = fixture.runDotfiles(home, ["verify", "--skip-brew"], {
        FAKE_MISE_LS_WARNING: "1",
      });
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stderr, /fake mise ls warning/);
    });
  });
});

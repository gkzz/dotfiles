import assert from "node:assert/strict";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it } from "node:test";
import { assertExit, repositoryRoot, run } from "./helpers/process.js";

function fixture(t, target = "~/.codex/config.toml/") {
  const root = mkdtempSync(path.join(os.tmpdir(), "codex merge "));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = path.join(root, "home");
  const config = path.join(home, ".codex/config.toml");
  mkdirSync(path.dirname(config), { recursive: true });
  // Use the real declaration without loading unrelated tools or dotfiles.
  const declarations = readFileSync(
    path.join(repositoryRoot, "mise.toml"),
    "utf8",
  )
    .split("\n")
    .filter((line) => line.startsWith(`"${target}`));
  assert.ok(declarations.length > 0);
  // Copy sources into the fixture so updates never edit the repository.
  const sources = path.join(root, "sources");
  mkdirSync(sources);
  const entries = declarations.map((line) =>
    line.replace(/source = "([^"]+)"/, (_, relative) => {
      const copy = path.join(sources, path.basename(relative));
      writeFileSync(copy, readFileSync(path.join(repositoryRoot, relative)));
      return `source = "${copy}"`;
    }),
  );
  writeFileSync(
    path.join(root, "mise.toml"),
    `[dotfiles]\n${entries.join("\n")}\n`,
  );
  const invoke = (...args) =>
    run("mise", ["-C", root, "dot", ...args], {
      cwd: root,
      env: {
        ...process.env,
        HOME: home,
        MISE_CONFIG_FILE: path.join(root, "mise.toml"),
        MISE_GLOBAL_CONFIG_FILE: path.join(root, "empty.toml"),
        MISE_STATE_DIR: path.join(root, "state"),
        MISE_DATA_DIR: path.join(root, "data"),
        MISE_CACHE_DIR: path.join(root, "cache"),
        MISE_TRUSTED_CONFIG_PATHS: root,
      },
    });
  return { root, home, config, invoke, sources };
}

describe("Codex", () => {
  describe("agent deployment", () => {
    it("copies the agent definition as a private regular file", (t) => {
      const { home, invoke } = fixture(t, "~/.codex/agents/code-analysis.toml");
      const agent = path.join(home, ".codex/agents/code-analysis.toml");
      assertExit(invoke("apply", "--yes"), 0, "agent apply");
      assert.equal(lstatSync(agent).isFile(), true);
      assert.equal(lstatSync(agent).mode & 0o777, 0o600);
      assert.equal(
        readFileSync(agent, "utf8"),
        readFileSync(
          path.join(repositoryRoot, ".agents/subagents/code-analysis.toml"),
          "utf8",
        ),
      );
    });
  });

  describe("configuration merge", () => {
    it("mise preserves local settings, reapplies shared keys and leaves merged config on unapply", (t) => {
      const { config, invoke } = fixture(t);
      const local =
        '# local settings\nmodel = "local-model"\nmodel_reasoning_effort = "high"\n[mcp_servers.example]\ncommand = "example"\n[projects."/tmp/project"]\ntrust_level = "trusted"\n';
      const original = `sandbox_mode = "read-only"\napproval_policy = "never"\napprovals_reviewer = "auto_review"\n${local}`;
      writeFileSync(config, original);
      assertExit(invoke("apply", "--dry-run"), 0, "dry-run");
      assert.equal(readFileSync(config, "utf8"), original);
      assertExit(invoke("apply", "--yes"), 0, "apply");
      const merged = readFileSync(config, "utf8");
      assert.match(merged, /sandbox_mode = "workspace-write"/);
      assert.match(merged, /approval_policy = "on-request"/);
      for (const line of local.trim().split("\n"))
        assert.ok(merged.includes(line), line);
      assert.match(merged, /model_reasoning_effort = "high"/);
      assert.match(merged, /approvals_reviewer = "user"/);
      assert.equal(lstatSync(config).isSymbolicLink(), false);
      assertExit(invoke("status", "--missing"), 0, "status");
      assertExit(invoke("apply", "--yes"), 0, "reapply");
      assert.equal(readFileSync(config, "utf8"), merged);
      writeFileSync(
        config,
        merged
          .replace('"on-request"', '"never"')
          .replace('"workspace-write"', '"read-only"')
          .replace(
            'approvals_reviewer = "user"',
            'approvals_reviewer = "auto_review"',
          ),
      );
      assert.notEqual(invoke("status", "--missing").status, 0);
      assertExit(invoke("apply", "--yes"), 0, "restore shared key");
      assert.equal(readFileSync(config, "utf8"), merged);
      assertExit(invoke("unapply", "--yes"), 0, "unapply");
      assert.equal(readFileSync(config, "utf8"), merged);
    });

    it("mise creates a private regular config on a new machine", (t) => {
      const { config, invoke } = fixture(t);
      assertExit(invoke("apply", "--dry-run"), 0, "new config dry-run");
      assert.equal(existsSync(config), false);
      assertExit(invoke("apply", "--yes"), 0, "new config");
      assert.equal(lstatSync(config).isFile(), true);
      assert.equal(lstatSync(config).mode & 0o777, 0o600);
      assert.match(
        readFileSync(config, "utf8"),
        /sandbox_mode = "workspace-write"/,
      );
      assert.match(readFileSync(config, "utf8"), /model = "gpt-6.1-sol"/);
      assert.match(
        readFileSync(config, "utf8"),
        /model_reasoning_effort = "low"/,
      );
    });
  });

  describe("shared rules deployment", () => {
    it("mise updates shared rules and preserves unmanaged rules", (t) => {
      const { home, sources, invoke } = fixture(
        t,
        "~/.codex/rules/shared.rules",
      );
      const rules = path.join(home, ".codex/rules");
      mkdirSync(rules, { recursive: true });
      for (const name of ["local.rules", "default.rules"])
        writeFileSync(path.join(rules, name), "# local\n");
      const shared = path.join(rules, "shared.rules");
      assertExit(invoke("apply", "--dry-run"), 0, "rules dry-run");
      assert.equal(existsSync(shared), false);
      assertExit(invoke("apply", "--yes"), 0, "rules apply");
      assert.equal(lstatSync(shared).isFile(), true);
      assert.equal(lstatSync(shared).mode & 0o777, 0o600);
      const updated = `${readFileSync(shared, "utf8")}# updated\n`;
      writeFileSync(path.join(sources, "shared.rules"), updated);
      assertExit(invoke("apply", "--yes"), 0, "rules update");
      assert.equal(readFileSync(shared, "utf8"), updated);
      assertExit(invoke("unapply", "--yes"), 0, "rules unapply");
      assert.equal(existsSync(shared), false);
      for (const name of ["local.rules", "default.rules"])
        assert.equal(readFileSync(path.join(rules, name), "utf8"), "# local\n");
    });
  });

  describe("command approval policy", () => {
    function policyFixture(t) {
      const { root, home, invoke } = fixture(t, "~/.codex/rules/shared.rules");
      assertExit(invoke("apply", "--yes"), 0, "deploy policy");
      const shared = path.join(home, ".codex/rules/shared.rules");
      const local = path.join(
        repositoryRoot,
        ".config/codex/local.rules.example",
      );
      const check = (args, extraRules = []) => {
        const result = run(
          "codex",
          [
            "execpolicy",
            "check",
            "--rules",
            shared,
            "--rules",
            local,
            ...extraRules.flatMap((rule) => ["--rules", rule]),
            "--",
            ...args,
          ],
          { env: { ...process.env, CODEX_HOME: path.join(home, ".codex") } },
        );
        assertExit(result, 0, args.join(" "));
        return JSON.parse(result.stdout);
      };
      return { root, check };
    }

    it("loads the deployed policy and local example with their inline checks", (t) => {
      const { check } = policyFixture(t);
      // Loading validates match/not_match examples for every shared rule.
      assert.equal(
        check(["git", "reset", "--hard", "HEAD"]).decision,
        "prompt",
      );
      assert.equal(check(["rm", "-rf", "directory"]).decision, "prompt");
      assert.equal(check(["gh", "pr", "view", "1"]).decision, "allow");
    });

    it("keeps the shared prompt when another file allows the same command", (t) => {
      const { root, check } = policyFixture(t);
      const allow = path.join(root, "allow.rules");
      writeFileSync(
        allow,
        'prefix_rule(pattern = ["git", "reset"], decision = "allow")\n',
      );
      assert.equal(
        check(["git", "reset", "--hard", "HEAD"], [allow]).decision,
        "prompt",
      );
    });
  });
});

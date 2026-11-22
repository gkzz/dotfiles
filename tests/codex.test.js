import assert from "node:assert/strict";
import { closeSync, constants, existsSync, lstatSync, mkdirSync, mkdtempSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { run, assertExit, repositoryRoot } from "./helpers/process.js";

function fixture(t, target = "~/.codex/config.toml/shared", source = ".config/codex/shared.toml") {
  const root = mkdtempSync(path.join(os.tmpdir(), "codex merge "));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = path.join(root, "home");
  const config = path.join(home, ".codex/config.toml");
  mkdirSync(path.dirname(config), { recursive: true });
  // Use the real declaration without loading unrelated tools or dotfiles.
  const declaration = readFileSync(path.join(repositoryRoot, "mise.toml"), "utf8")
    .split("\n").find((line) => line.startsWith(`"${target}"`));
  assert.ok(declaration);
  writeFileSync(path.join(root, "mise.toml"), `[dotfiles]\n${declaration.replace(source, path.join(repositoryRoot, source))}\n`);
  const invoke = (...args) => run("mise", ["-C", root, "dot", ...args], {
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
  return { root, home, config, invoke };
}

for (const existingLink of [false, true]) {
  test(`mise deploys a regular agent definition ${existingLink ? "over the previous symlink" : "on a new machine"}`, (t) => {
    const source = path.join(repositoryRoot, ".agents/subagents/code-analysis.toml");
    const { home, invoke } = fixture(t, "~/.codex/agents/code-analysis.toml", ".agents/subagents/code-analysis.toml");
    const agent = path.join(home, ".codex/agents/code-analysis.toml");
    const original = readFileSync(source, "utf8");
    if (existingLink) {
      mkdirSync(path.dirname(agent), { recursive: true });
      symlinkSync(source, agent);
    }
    assertExit(invoke("apply", "--dry-run"), 0, "agent dry-run");
    assert.equal(existsSync(agent), existingLink);
    if (existingLink) assert.equal(lstatSync(agent).isSymbolicLink(), true);
    assertExit(invoke("apply", "--yes"), 0, "agent apply");
    assert.equal(lstatSync(agent).isFile(), true);
    assert.equal(readFileSync(agent, "utf8"), original);
    // Codex uses O_NOFOLLOW when opening agent definitions on Unix.
    const fd = openSync(agent, constants.O_RDONLY | constants.O_NOFOLLOW);
    closeSync(fd);
    assertExit(invoke("status", "--missing"), 0, "agent status");
    assertExit(invoke("apply", "--yes"), 0, "agent reapply");
    assert.equal(readFileSync(source, "utf8"), original);
    assertExit(invoke("unapply", "--yes"), 0, "agent unapply");
    assert.equal(existsSync(agent), false);
    assert.equal(readFileSync(source, "utf8"), original);
  });
}

test("mise preserves local settings, reapplies shared keys and leaves merged config on unapply", (t) => {
  const { config, invoke } = fixture(t);
  const local = '# local settings\nmodel = "local-model"\n[mcp_servers.example]\ncommand = "example"\n[projects."/tmp/project"]\ntrust_level = "trusted"\n';
  const original = 'sandbox_mode = "read-only"\napproval_policy = "never"\n' + local;
  writeFileSync(config, original);
  assertExit(invoke("apply", "--dry-run"), 0, "dry-run");
  assert.equal(readFileSync(config, "utf8"), original);
  assertExit(invoke("apply", "--yes"), 0, "apply");
  const merged = readFileSync(config, "utf8");
  assert.match(merged, /sandbox_mode = "workspace-write"/);
  assert.match(merged, /approval_policy = "on-request"/);
  assert.ok(merged.includes(local));
  assert.equal(lstatSync(config).isSymbolicLink(), false);
  assertExit(invoke("status", "--missing"), 0, "status");
  assertExit(invoke("apply", "--yes"), 0, "reapply");
  assert.equal(readFileSync(config, "utf8"), merged);
  writeFileSync(config, merged.replace('"on-request"', '"never"'));
  assert.notEqual(invoke("status", "--missing").status, 0);
  assertExit(invoke("apply", "--yes"), 0, "restore shared key");
  assert.equal(readFileSync(config, "utf8"), merged);
  assertExit(invoke("unapply", "--yes"), 0, "unapply");
  assert.equal(readFileSync(config, "utf8"), merged);
});

test("mise creates a private regular config on a new machine", (t) => {
  const { config, invoke } = fixture(t);
  assertExit(invoke("apply", "--yes"), 0, "new config");
  assert.equal(lstatSync(config).isFile(), true);
  assert.equal(lstatSync(config).mode & 0o777, 0o600);
  assert.match(readFileSync(config, "utf8"), /sandbox_mode = "workspace-write"/);
});

for (const kind of ["invalid TOML", "foreign symlink"]) {
  test(`mise refuses ${kind} without changing the original`, (t) => {
    const { root, config, invoke } = fixture(t);
    if (kind === "invalid TOML") writeFileSync(config, "[invalid");
    else {
      const other = path.join(root, "other.toml");
      writeFileSync(other, 'model = "untouched"\n');
      symlinkSync(other, config);
    }
    const before = readFileSync(config, "utf8");
    assert.notEqual(invoke("apply", "--yes").status, 0);
    assert.equal(readFileSync(config, "utf8"), before);
    assert.equal(lstatSync(config).isSymbolicLink(), kind === "foreign symlink");
  });
}

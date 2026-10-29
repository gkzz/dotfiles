import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { run, assertExit } from "./helpers/process.js";

test("make finds mise using its configured PATH, including paths with spaces", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "dotfiles-make-"));
  try {
    const bin = path.join(root, "brew bin");
    mkdirSync(bin);
    writeFileSync(path.join(bin, "mise"), '#!/bin/sh\nprintf "%s\\n" "$MISE_CONFIG_FILE" "$@"\n', { mode: 0o755 });
    const result = run("make", ["install", `PATH=${bin}:/usr/bin:/bin`]);
    assertExit(result, 0, "make install with mise outside the inherited PATH");
    assert.match(result.stdout, /mise-operations\.toml\nrun\ndotfiles:install\n/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("make explains how to install missing mise while help remains available", () => {
  const options = { env: { ...process.env, MISE: "" } };
  const result = run("make", ["install", "MISE="], options);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /mise was not found; run make setup first/);
  assertExit(run("make", ["help", "MISE="], options), 0, "help without mise");
});

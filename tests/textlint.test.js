import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { createLinter, loadTextlintrc } from "textlint";
import { repositoryRoot } from "./helpers/process.js";

const descriptor = await loadTextlintrc({
  configFilePath: path.join(repositoryRoot, ".config/textlint/.textlintrc.ja.json"),
});

function fixture(t) {
  const cwd = mkdtempSync(path.join(os.tmpdir(), "dotfiles-textlint-"));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  for (const name of ["README.md", "docs/nested/guide.md", ".agents/skills/example/SKILL.md", "docs/ignored.md", "node_modules/example/skip.md", ".git/skip.md"]) {
    const file = path.join(cwd, name);
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, "テストです。\n");
  }
  writeFileSync(path.join(cwd, ".textlintignore"), "# Excluded documentation\ndocs/ignored.md\n");
  return {
    cwd,
    linter: createLinter({ descriptor, cwd, ignoreFilePath: ".textlintignore" }),
  };
}

test("textlint discovers nested and hidden documentation while respecting ignores", async (t) => {
  const { cwd, linter } = fixture(t);
  const results = await linter.lintFiles(["**/*.md"]);
  assert.deepEqual(
    results.map((result) => path.relative(cwd, result.filePath).split(path.sep).join("/")).sort(),
    [".agents/skills/example/SKILL.md", "README.md", "docs/nested/guide.md"],
  );
});

test("textlint accepts a pattern whose matches are all ignored", async (t) => {
  const { linter } = fixture(t);
  assert.deepEqual(await linter.lintFiles(["docs/ignored.md"]), []);
});

test("textlint reports a pattern with no matching files", async (t) => {
  const { linter } = fixture(t);
  await assert.rejects(linter.lintFiles(["missing/**/*.md"]), {
    name: "TextlintFileSearchError",
  });
});

import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it } from "node:test";
import { assertExit, repositoryRoot, run } from "./helpers/process.js";

describe("documentation lint integration", () => {
  it("uses the production script and ignore file to select documentation", (t) => {
    // macOS temporary paths can resolve from /var to /private/var.
    const cwd = realpathSync(
      mkdtempSync(path.join(os.tmpdir(), "dotfiles-textlint-")),
    );
    t.after(() => rmSync(cwd, { recursive: true, force: true }));
    for (const name of [
      "README.md",
      "docs/nested/guide.md",
      ".agents/skills/example/SKILL.md",
      ".agents/skills/renodash-dashboard/SKILL.md",
      ".agents/skills/renodash-weekly-review/SKILL.md",
      "other/note.md",
      "node_modules/example/skip.md",
      ".git/skip.md",
    ]) {
      const file = path.join(cwd, name);
      mkdirSync(path.dirname(file), { recursive: true });
      writeFileSync(file, "テストです。\n");
    }
    for (const name of [".textlintrc.ja.json", ".textlintignore"]) {
      const relative = path.join(".config/textlint", name);
      mkdirSync(path.dirname(path.join(cwd, relative)), { recursive: true });
      writeFileSync(
        path.join(cwd, relative),
        readFileSync(path.join(repositoryRoot, relative)),
      );
    }
    // Resolve the production rules and executable without installing dependencies.
    symlinkSync(
      path.join(repositoryRoot, "node_modules/textlint"),
      path.join(cwd, "node_modules/textlint"),
      "dir",
    );
    symlinkSync(
      path.join(
        repositoryRoot,
        "node_modules/textlint-rule-preset-ja-technical-writing",
      ),
      path.join(cwd, "node_modules/textlint-rule-preset-ja-technical-writing"),
      "dir",
    );
    const { scripts } = JSON.parse(
      readFileSync(path.join(repositoryRoot, "package.json"), "utf8"),
    );
    const result = run(
      "/bin/sh",
      [
        "-c",
        `${scripts["lint:docs"]} --format json --output-file results.json`,
      ],
      {
        cwd,
        env: {
          ...process.env,
          PATH: `${path.join(repositoryRoot, "node_modules/.bin")}${path.delimiter}${process.env.PATH}`,
        },
      },
    );
    assertExit(result, 0, "production documentation lint command");
    assert.deepEqual(
      JSON.parse(readFileSync(path.join(cwd, "results.json"), "utf8"))
        .map((entry) =>
          path.relative(cwd, entry.filePath).split(path.sep).join("/"),
        )
        .sort(),
      [".agents/skills/example/SKILL.md", "README.md", "docs/nested/guide.md"],
    );
  });
});

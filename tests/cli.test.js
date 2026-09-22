import path from "node:path";
import { describe, it } from "node:test";

import { assertExit, repositoryRoot, run } from "./helpers/process.js";

/**
 * CLI の公開インターフェースを検証する。
 * 未指定・廃止済み・同時指定できない引数を終了コード 2 で拒否することが対象。
 */
const dotfiles = path.join(repositoryRoot, "bin/dotfiles");

describe("CLI parser", () => {
  const invalidInvocations = [
    { name: "empty invocation", args: [] },
    { name: "removed prepare phase", args: ["--prepare"] },
    { name: "removed target option", args: ["install", "--target", "/tmp"] },
    { name: "apply option on verify", args: ["verify", "--apply"] },
    { name: "force option on uninstall", args: ["uninstall", "--force"] },
    {
      name: "conflicting apply then dry-run",
      args: ["install", "--apply", "--dry-run"],
    },
    {
      name: "conflicting dry-run then apply",
      args: ["install", "--dry-run", "--apply"],
    },
    { name: "dry-run option on verify", args: ["verify", "--dry-run"] },
  ];

  for (const { name, args } of invalidInvocations) {
    it(name, () => {
      assertExit(run(dotfiles, args), 2, `${dotfiles} ${args.join(" ")}`);
    });
  }
});

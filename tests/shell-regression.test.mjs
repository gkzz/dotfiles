import path from "node:path";
import { describe, it } from "node:test";

import { assertExit, repositoryRoot, run } from "./helpers/process.mjs";

/**
 * node:testへの移行中も、未移行の機能別Bashテストを回帰テストとして実行する。
 * 各ファイルの詳細なassertionは移行先の.test.mjsができるまでBash側が保持する。
 */
describe("Bash regression tests awaiting node:test migration", () => {
  for (const file of ["bootstrap.sh", "check-diagnostics.sh"]) {
    it(`passes ${file}`, () => {
      const script = path.join(repositoryRoot, "tests", file);
      assertExit(run(script), 0, script);
    });
  }
});

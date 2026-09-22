import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);

/** CLIをrepository rootから実行し、終了状態と標準出力を返す。 */
export function run(command, args = [], options = {}) {
  return spawnSync(command, args, {
    cwd: repositoryRoot,
    encoding: "utf8",
    ...options,
  });
}

/** 終了コードが違う場合はstdoutとstderrをまとめて表示する。 */
export function assertExit(result, expected, context) {
  assert.equal(
    result.status,
    expected,
    `${context}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
  );
}

/** 2つの文字列が存在し、firstがsecondより前に現れることを確認する。 */
export function assertBefore(value, first, second, context = "") {
  const firstIndex = value.indexOf(first);
  const secondIndex = value.indexOf(second);
  if (firstIndex === -1) assert.fail(`${context}: missing ${first}`);
  if (secondIndex === -1) assert.fail(`${context}: missing ${second}`);
  if (firstIndex >= secondIndex)
    assert.fail(`${context}: ${first} must precede ${second}`);
}

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { readQuotedValue } from "./repository-config.js";

describe("readQuotedValue", () => {
  it("TOMLの空白と行末コメントを受け入れる", () => {
    const config = `
      min_version="2026.8.15" # bootstrap version

      [ tools ] # development tools
      node = "24.19.0" # runtime version
    `;

    assert.equal(readQuotedValue(config, "", "min_version"), "2026.8.15");
    assert.equal(readQuotedValue(config, "tools", "node"), "24.19.0");
  });

  it("値の重複を拒否する", () => {
    const config = `
      [tools]
      node = "24.19.0"
      node = "24.20.0"
    `;

    assert.throws(
      () => readQuotedValue(config, "tools", "node", "mise.toml"),
      /expected exactly one \[tools] node in mise\.toml/,
    );
  });
});

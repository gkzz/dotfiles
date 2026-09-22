import { readFileSync } from "node:fs";
import path from "node:path";

import { repositoryRoot } from "./process.js";

const miseConfigPath = path.join(repositoryRoot, ".config/mise/config.toml");
const miseConfig = readFileSync(miseConfigPath, "utf8");

export function readQuotedValue(config, section, key, configPath = "config") {
  let currentSection = "";
  const values = [];

  for (const line of config.split(/\r?\n/)) {
    const sectionMatch = line.match(/^\s*\[([^\]]+)]\s*(?:#.*)?$/);
    if (sectionMatch) {
      currentSection = sectionMatch[1].trim();
      continue;
    }
    if (currentSection !== section) continue;

    const valueMatch = line.match(
      new RegExp(
        `^\\s*${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*=\\s*"([^"]+)"\\s*(?:#.*)?$`,
      ),
    );
    if (valueMatch) values.push(valueMatch[1]);
  }

  if (values.length !== 1) {
    throw new Error(
      `expected exactly one ${section ? `[${section}] ` : ""}${key} in ${configPath}`,
    );
  }
  return values[0];
}

export const repositoryConfig = Object.freeze({
  miseMinimumVersion: readQuotedValue(
    miseConfig,
    "",
    "min_version",
    miseConfigPath,
  ),
  tools: Object.freeze({
    node: readQuotedValue(miseConfig, "tools", "node", miseConfigPath),
  }),
});

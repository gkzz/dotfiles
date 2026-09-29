import { createHash } from "node:crypto";
import {
  closeSync,
  lstatSync,
  openSync,
  readFileSync,
  readlinkSync,
  readSync,
  writeFileSync,
} from "node:fs";

// findのNUL区切りをBufferのまま扱い、UTF-8でないファイル名も保持する。
const [home, list] = process.argv.slice(2);
const prefix = Buffer.from(`${home}/`);
const entries = readFileSync(list);
const records = [];
const chunk = Buffer.alloc(1024 * 1024);

try {
  let start = 0;
  for (let end = 0; end < entries.length; end++) {
    if (entries[end] !== 0) continue;
    const entry = entries.subarray(start, end);
    start = end + 1;
    if (!entry.subarray(0, prefix.length).equals(prefix)) {
      throw new Error("entry must be inside HOME");
    }
    const relative = entry.subarray(prefix.length).toString("hex");
    const stat = lstatSync(entry);
    const mode = (stat.mode & 0o7777).toString(8);
    if (stat.isSymbolicLink()) {
      const target = readlinkSync(entry, { encoding: "buffer" }).toString(
        "hex",
      );
      records.push(`${relative}\tl\t${target}`);
    } else if (stat.isDirectory()) {
      records.push(`${relative}\td\t${mode}`);
    } else if (stat.isFile()) {
      const hash = createHash("sha256");
      const descriptor = openSync(entry, "r");
      try {
        while (true) {
          const length = readSync(descriptor, chunk, 0, chunk.length, null);
          if (length === 0) break;
          hash.update(chunk.subarray(0, length));
        }
      } finally {
        closeSync(descriptor);
      }
      records.push(`${relative}\tf\t${mode}\t${hash.digest("hex")}`);
    } else {
      throw new Error(`unsupported entry type: ${entry.toString()}`);
    }
  }
  records.sort();
  writeFileSync(1, records.length ? `${records.join("\n")}\n` : "");
} catch (error) {
  writeFileSync(2, `error: ${error.message}\n`);
  process.exitCode = 1;
}

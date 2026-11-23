import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";

const repo = path.resolve(import.meta.dirname, "..");

function startShell({ platform = "Linux", wsl = false, tools = true, localMise = true } = {}) {
  const root = mkdtempSync(path.join(os.tmpdir(), "dotfiles-shell-"));
  try {
    const home = path.join(root, "home");
    const bin = path.join(root, "bin");
    const dotfiles = path.join(root, "dotfiles");
    for (const dir of [home, bin, `${home}/.local/bin`, `${dotfiles}/bash`]) mkdirSync(dir, { recursive: true });
    writeFileSync(`${root}/osrelease`, wsl ? "microsoft" : "linux");
    const script = (file, body) => writeFileSync(file, `#!/bin/bash\n${body}\n`, { mode: 0o755 });
    // Keep the dispatch and platform scripts intact apart from fixed host tool paths.
    for (const file of [".bashrc", "bash/linux.bash", "bash/wsl.bash", "bash/mac.bash"]) {
      let source = readFileSync(path.join(repo, file), "utf8");
      source = source.replaceAll("/proc/sys/kernel/osrelease", `${root}/osrelease`)
        .replaceAll("/home/linuxbrew/.linuxbrew/bin/brew", `${bin}/brew`)
        .replaceAll("/opt/homebrew/bin/brew", `${bin}/brew`)
        .replaceAll("/usr/local/bin/brew", `${bin}/brew`)
        .replaceAll("/usr/bin/dircolors", `${bin}/dircolors`)
        .replaceAll("/usr/bin/lesspipe", `${bin}/lesspipe`);
      writeFileSync(path.join(dotfiles, file), source);
    }
    // Retain PATH setup; omit unrelated completion and prompt dependencies on the host.
    writeFileSync(`${dotfiles}/bash/path.bash`, readFileSync(`${repo}/bash/path.bash`));
    script(`${bin}/uname`, `echo '${platform}'`);
    script(`${bin}/grep`, '/usr/bin/grep "$@"');
    script(`${bin}/dirname`, '/usr/bin/dirname "$@"');
    if (tools) {
      script(`${bin}/brew`, 'echo brew >> "$CALLS"; echo "export BREW_READY=1"');
      script(localMise ? `${home}/.local/bin/mise` : `${bin}/mise`, 'echo "mise:$*:brew=$BREW_READY" >> "$CALLS"; echo \'export PATH="$HOME/managed/bin:$PATH"\'');
      mkdirSync(`${home}/managed/bin`, { recursive: true });
      script(`${home}/managed/bin/managed-tool`, 'echo managed-ok');
      script(`${bin}/direnv`, 'echo "direnv:$*" >> "$CALLS"');
      script(`${bin}/dircolors`, 'echo dircolors >> "$CALLS"');
      script(`${bin}/lesspipe`, 'echo lesspipe >> "$CALLS"');
      // No real agent or key access is allowed by this fixture.
      script(`${bin}/ssh-agent`, 'echo ssh-agent >> "$CALLS"');
      script(`${bin}/ssh-add`, 'echo ssh-add >> "$CALLS"; exit 0');
      mkdirSync(`${home}/.ssh`);
      writeFileSync(`${home}/.ssh/id_ed25519_wsl2`, "fixture");
    }
    writeFileSync(`${home}/.bashrc.local`, 'echo local >> "$CALLS"\n');
    const result = spawnSync("/bin/bash", ["--noprofile", "--rcfile", `${dotfiles}/.bashrc`, "-ic", tools ? "managed-tool" : "echo shell-ok"], {
      env: { HOME: home, PATH: bin, CALLS: `${root}/calls`, TERM: "dumb" }, encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr);
    const calls = readFileSync(`${root}/calls`, "utf8").trim().split("\n");
    return { calls, stdout: result.stdout };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

for (const localMise of [true, false]) {
  test(`ordinary Linux activates tools with mise in ${localMise ? "HOME" : "PATH"}`, () => {
    const { calls, stdout } = startShell({ localMise });
    assert.deepEqual(calls, ["dircolors", "lesspipe", "brew", "mise:activate bash:brew=1", "direnv:hook bash", "local"]);
    assert.equal(stdout.trim(), "managed-ok");
  });
}

test("WSL runs common initialization once before SSH initialization", () => {
  const { calls } = startShell({ wsl: true });
  assert.deepEqual(calls, ["dircolors", "lesspipe", "brew", "mise:activate bash:brew=1", "direnv:hook bash", "ssh-add", "ssh-add", "local"]);
});

test("macOS activates tools without Linux or WSL initialization", () => {
  const { calls } = startShell({ platform: "Darwin" });
  assert.deepEqual(calls, ["brew", "mise:activate bash:brew=1", "direnv:hook bash", "local"]);
});

for (const options of [{}, { wsl: true }, { platform: "Darwin" }]) {
  test(`shell starts without optional tools: ${JSON.stringify(options)}`, () => {
    const { calls, stdout } = startShell({ ...options, tools: false });
    assert.deepEqual(calls, ["local"]);
    assert.equal(stdout.trim(), "shell-ok");
  });
}

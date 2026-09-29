import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, it } from "node:test";

import { repositoryRoot } from "./helpers/process.js";

const hook = path.join(repositoryRoot, "git/hooks/pre-commit");
const temporaryRoots = [];

function run(command, args, options = {}) {
  return spawnSync(command, args, { encoding: "utf8", ...options });
}

function git(repository, ...args) {
  const result = run("git", args, { cwd: repository });
  assert.equal(
    result.status,
    0,
    `git ${args.join(" ")}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
  );
}

function executable(file, contents) {
  writeFileSync(file, contents);
  chmodSync(file, 0o755);
}

function hookEnvironment(root, values = {}) {
  const home = path.join(root, "home");
  mkdirSync(home, { recursive: true });
  return { ...process.env, HOME: home, ...values };
}

function repository() {
  const root = mkdtempSync(path.join(os.tmpdir(), "dotfiles-hook-test."));
  temporaryRoots.push(root);
  git(root, "init", "--quiet");
  git(root, "config", "user.name", "Test User");
  git(root, "config", "user.email", "test@example.com");
  git(root, "config", "commit.gpgsign", "false");
  return root;
}

afterEach(() => {
  for (const root of temporaryRoots.splice(0)) {
    rmSync(root, { recursive: true, force: true });
  }
});

describe("global pre-commit hook", () => {
  it("repository hookを先に実行し、その失敗時はSecretlintを起動しない", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const dockerMarker = path.join(root, "docker-ran");
    mkdirSync(fakeBin);
    mkdirSync(path.join(root, ".git/hooks"), { recursive: true });
    executable(
      path.join(root, ".git/hooks/pre-commit"),
      "#!/usr/bin/env bash\nprintf '%s\\n' 'repository hook failure' >&2\nexit 29\n",
    );
    executable(
      path.join(fakeBin, "docker"),
      '#!/usr/bin/env bash\nprintf ran >"$DOCKER_MARKER"\n',
    );
    writeFileSync(path.join(root, "content.txt"), "content\n");
    git(root, "add", "content.txt");

    const result = run(hook, [], {
      cwd: root,
      env: hookEnvironment(root, {
        DOCKER_MARKER: dockerMarker,
        PATH: `${fakeBin}:${process.env.PATH}`,
      }),
    });

    assert.equal(result.status, 29);
    assert.match(result.stderr, /repository hook failure/);
    assert.equal(existsSync(dockerMarker), false);
  });

  it("runs the repository hook first and scans only staged contents", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const marker = path.join(root, "local-hook-ran");
    mkdirSync(fakeBin);

    writeFileSync(path.join(root, "space name.txt"), "baseline content\n");
    writeFileSync(path.join(root, "deleted.txt"), "remove me\n");
    git(root, "add", "space name.txt", "deleted.txt");
    git(root, "commit", "--quiet", "--no-verify", "-m", "fixture");
    writeFileSync(path.join(root, "space name.txt"), "staged content\n");
    git(root, "add", "space name.txt");
    writeFileSync(path.join(root, "space name.txt"), "unstaged content\n");
    rmSync(path.join(root, "deleted.txt"));
    git(root, "add", "deleted.txt");

    mkdirSync(path.join(root, ".git/hooks"), { recursive: true });
    executable(
      path.join(root, ".git/hooks/pre-commit"),
      '#!/usr/bin/env bash\nprintf local >"$HOOK_MARKER"\n',
    );
    executable(
      path.join(fakeBin, "docker"),
      `#!/usr/bin/env bash
set -euo pipefail
[ -f "$HOOK_MARKER" ]
mount=
for argument in "$@"; do
  case "$argument" in
    type=bind,source=*,target=/scan,readonly) mount=$argument ;;
  esac
done
[ -n "$mount" ]
source=\${mount#type=bind,source=}
source=\${source%,target=/scan,readonly}
[ "$(cat "$source/repository/space name.txt")" = "staged content" ]
[ ! -e "$source/repository/deleted.txt" ]
printf '%s\\n' "$*" >"$DOCKER_ARGUMENTS"
`,
    );

    const dockerArguments = path.join(root, "docker-arguments");
    const result = run(hook, [], {
      cwd: root,
      env: {
        ...hookEnvironment(root),
        DOCKER_ARGUMENTS: dockerArguments,
        HOOK_MARKER: marker,
        PATH: `${fakeBin}:${process.env.PATH}`,
      },
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(marker, "utf8"), "local");
    assert.match(
      readFileSync(dockerArguments, "utf8"),
      /--network none .*target=\/scan,readonly --workdir \/scan\/repository secretlint\/secretlint:v13\.0\.4@sha256:3b3f8d2ea61ab21ce1f8185d69e7cad12e040fa5370d8f5462dd366fd24ef765 secretlint --no-gitignore --secretlintignore \/scan\/\.secretlintignore\.effective --secretlintrc \/scan\/\.secretlintrc\.default\.json \.\/space name\.txt/,
    );
    assert.doesNotMatch(result.stderr, /ignored null byte/);
  });

  it("materializes a staged path beginning with a colon", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    mkdirSync(fakeBin);
    writeFileSync(path.join(root, ":secret.txt"), "staged colon path\n");
    git(root, "add", "./:secret.txt");

    executable(
      path.join(fakeBin, "docker"),
      `#!/usr/bin/env bash
set -euo pipefail
mount=
for argument in "$@"; do
  case "$argument" in
    type=bind,source=*,target=/scan,readonly) mount=$argument ;;
  esac
done
[ -n "$mount" ]
source=\${mount#type=bind,source=}
source=\${source%,target=/scan,readonly}
[ "$(cat "$source/repository/:secret.txt")" = "staged colon path" ]
[ "\${@: -1}" = "./:secret.txt" ]
`,
    );

    const result = run(hook, [], {
      cwd: root,
      env: {
        ...hookEnvironment(root),
        PATH: `${fakeBin}:${process.env.PATH}`,
      },
    });

    assert.equal(result.status, 0, result.stderr);
  });

  it("returns the secretlint container status and removes staged snapshots", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const snapshot = path.join(root, "snapshot-path");
    mkdirSync(fakeBin);
    writeFileSync(path.join(root, "secret.txt"), "credential\n");
    git(root, "add", "secret.txt");

    executable(
      path.join(fakeBin, "docker"),
      `#!/usr/bin/env bash
for argument in "$@"; do
  case "$argument" in
    type=bind,source=*,target=/scan,readonly)
      source=\${argument#type=bind,source=}
      source=\${source%,target=/scan,readonly}
      printf '%s' "$source" >"$SNAPSHOT_PATH"
      ;;
  esac
done
exit 23
`,
    );

    const result = run(hook, [], {
      cwd: root,
      env: {
        ...hookEnvironment(root),
        PATH: `${fakeBin}:${process.env.PATH}`,
        SNAPSHOT_PATH: snapshot,
      },
    });

    assert.equal(result.status, 23);
    assert.equal(existsSync(readFileSync(snapshot, "utf8")), false);
  });

  it("does not require Docker when no files are staged", () => {
    const root = repository();
    const result = run(hook, [], { cwd: root, env: hookEnvironment(root) });
    assert.equal(result.status, 0, result.stderr);
  });

  it("fails closed when listing staged files fails", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const diffCount = path.join(root, "diff-count");
    const dockerMarker = path.join(root, "docker-ran");
    mkdirSync(fakeBin);
    writeFileSync(path.join(root, "staged.txt"), "staged\n");
    git(root, "add", "staged.txt");

    executable(
      path.join(fakeBin, "git"),
      `#!/usr/bin/env bash
if [ "$1" = diff ]; then
  count=0
  [ ! -f "$DIFF_COUNT" ] || count=$(cat "$DIFF_COUNT")
  count=$((count + 1))
  printf '%s' "$count" >"$DIFF_COUNT"
  if [ "$count" -eq 2 ]; then
    exit 23
  fi
fi
exec /usr/bin/git "$@"
`,
    );
    executable(
      path.join(fakeBin, "docker"),
      '#!/usr/bin/env bash\nprintf ran >"$DOCKER_MARKER"\n',
    );

    const result = run(hook, [], {
      cwd: root,
      env: hookEnvironment(root, {
        DIFF_COUNT: diffCount,
        DOCKER_MARKER: dockerMarker,
        PATH: `${fakeBin}:${process.env.PATH}`,
      }),
    });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /failed to list staged files/);
    assert.equal(existsSync(dockerMarker), false);
  });

  it("explains that Docker is required when staged files exist", () => {
    const root = repository();
    const minimalBin = path.join(root, "minimal-bin");
    mkdirSync(minimalBin);
    symlinkSync("/usr/bin/git", path.join(minimalBin, "git"));
    symlinkSync("/usr/bin/mktemp", path.join(minimalBin, "mktemp"));
    writeFileSync(path.join(root, "staged.txt"), "staged\n");
    git(root, "add", "staged.txt");

    const result = run("/bin/bash", [hook], {
      cwd: root,
      env: hookEnvironment(root, { PATH: minimalBin }),
    });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /Docker is required to run secretlint/);
  });

  it("scans a staged type change", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const marker = path.join(root, "docker-ran");
    mkdirSync(fakeBin);
    writeFileSync(path.join(root, "changed-type"), "regular file\n");
    git(root, "add", "changed-type");
    git(root, "commit", "--quiet", "--no-verify", "-m", "fixture");
    rmSync(path.join(root, "changed-type"));
    symlinkSync("target", path.join(root, "changed-type"));
    git(root, "add", "changed-type");

    executable(
      path.join(fakeBin, "docker"),
      '#!/usr/bin/env bash\nprintf ran >"$DOCKER_MARKER"\n',
    );

    const result = run(hook, [], {
      cwd: root,
      env: hookEnvironment(root, {
        DOCKER_MARKER: marker,
        PATH: `${fakeBin}:${process.env.PATH}`,
      }),
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(marker, "utf8"), "ran");
  });

  it("skips Secretlint when only a gitlink is staged", () => {
    const root = repository();
    const minimalBin = path.join(root, "minimal-bin");
    mkdirSync(minimalBin);
    symlinkSync("/usr/bin/git", path.join(minimalBin, "git"));
    symlinkSync("/usr/bin/mktemp", path.join(minimalBin, "mktemp"));
    writeFileSync(path.join(root, "content.txt"), "baseline\n");
    git(root, "add", "content.txt");
    git(root, "commit", "--quiet", "--no-verify", "-m", "fixture");
    const commit = run("git", ["rev-parse", "HEAD"], {
      cwd: root,
    }).stdout.trim();
    git(
      root,
      "update-index",
      "--add",
      "--cacheinfo",
      `160000,${commit},vendor/example`,
    );

    const result = run("/bin/bash", [hook], {
      cwd: root,
      env: hookEnvironment(root, { PATH: minimalBin }),
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, "");
  });

  it("merges the global ignore with the staged repository ignore", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const capturedIgnore = path.join(root, "captured-ignore");
    const env = hookEnvironment(root, {
      CAPTURED_IGNORE: capturedIgnore,
      PATH: `${fakeBin}:${process.env.PATH}`,
    });
    mkdirSync(fakeBin);
    writeFileSync(path.join(env.HOME, ".secretlintignore"), "global/**\n");
    writeFileSync(path.join(root, ".secretlintignore"), "staged/**\n");
    mkdirSync(path.join(root, "nested"));
    writeFileSync(path.join(root, "nested/content.txt"), "content\n");
    git(root, "add", ".secretlintignore", "nested/content.txt");
    writeFileSync(path.join(root, ".secretlintignore"), "unstaged/**\n");

    for (const command of ["cat", "mkdir"]) {
      const resolved = run("bash", [
        "-c",
        `command -v ${command}`,
      ]).stdout.trim();
      executable(
        path.join(fakeBin, command),
        `#!/usr/bin/env bash
for argument in "$@"; do
  [ "$argument" != -- ] || exit 64
done
exec "${resolved}" "$@"
`,
      );
    }

    executable(
      path.join(fakeBin, "docker"),
      `#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
  case "$argument" in
    type=bind,source=*,target=/scan,readonly)
      source=\${argument#type=bind,source=}
      source=\${source%,target=/scan,readonly}
      cp "$source/.secretlintignore.effective" "$CAPTURED_IGNORE"
      ;;
  esac
done
`,
    );

    const result = run(hook, [], { cwd: root, env });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(
      readFileSync(capturedIgnore, "utf8"),
      "global/**\n\nstaged/**\n\n",
    );
  });

  it("does not apply an unstaged repository ignore after staged deletion", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const capturedIgnore = path.join(root, "captured-ignore");
    const env = hookEnvironment(root, {
      CAPTURED_IGNORE: capturedIgnore,
      PATH: `${fakeBin}:${process.env.PATH}`,
    });
    mkdirSync(fakeBin);
    writeFileSync(path.join(env.HOME, ".secretlintignore"), "global/**\n");
    writeFileSync(path.join(root, ".secretlintignore"), "tracked/**\n");
    writeFileSync(path.join(root, "content.txt"), "baseline\n");
    git(root, "add", ".secretlintignore", "content.txt");
    git(root, "commit", "--quiet", "--no-verify", "-m", "fixture");
    git(root, "rm", "--quiet", ".secretlintignore");
    writeFileSync(path.join(root, ".secretlintignore"), "untracked/**\n");
    writeFileSync(path.join(root, "content.txt"), "changed\n");
    git(root, "add", "content.txt");

    executable(
      path.join(fakeBin, "docker"),
      `#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
  case "$argument" in
    type=bind,source=*,target=/scan,readonly)
      source=\${argument#type=bind,source=}
      source=\${source%,target=/scan,readonly}
      cp "$source/.secretlintignore.effective" "$CAPTURED_IGNORE"
      ;;
  esac
done
`,
    );

    const result = run(hook, [], { cwd: root, env });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(capturedIgnore, "utf8"), "global/**\n\n");
  });

  it("keeps a staged .secretlintignore.effective in the scan", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const marker = path.join(root, "staged-effective-ignore");
    mkdirSync(fakeBin);
    writeFileSync(
      path.join(root, ".secretlintignore.effective"),
      "staged content\n",
    );
    git(root, "add", ".secretlintignore.effective");

    executable(
      path.join(fakeBin, "docker"),
      `#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
  case "$argument" in
    type=bind,source=*,target=/scan,readonly)
      source=\${argument#type=bind,source=}
      source=\${source%,target=/scan,readonly}
      [ "$(cat "$source/repository/.secretlintignore.effective")" = "staged content" ]
      [ -f "$source/.secretlintignore.effective" ]
      printf scanned >"$SCAN_MARKER"
      ;;
  esac
done
`,
    );

    const result = run(hook, [], {
      cwd: root,
      env: hookEnvironment(root, {
        PATH: `${fakeBin}:${process.env.PATH}`,
        SCAN_MARKER: marker,
      }),
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(marker, "utf8"), "scanned");
  });

  it("uses committed Secretlint configuration from the index", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const marker = path.join(root, "config-found");
    mkdirSync(fakeBin);
    writeFileSync(
      path.join(root, ".secretlintrc.json"),
      '{"rules":[{"id":"@secretlint/secretlint-rule-preset-recommend"}]}\n',
    );
    writeFileSync(path.join(root, "content.txt"), "baseline\n");
    git(root, "add", ".secretlintrc.json", "content.txt");
    git(root, "commit", "--quiet", "--no-verify", "-m", "fixture");
    writeFileSync(path.join(root, ".secretlintrc.json"), '{"rules":[]}\n');
    writeFileSync(path.join(root, "content.txt"), "staged\n");
    git(root, "add", "content.txt");

    executable(
      path.join(fakeBin, "docker"),
      `#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
  case "$argument" in
    type=bind,source=*,target=/scan,readonly)
      source=\${argument#type=bind,source=}
      source=\${source%,target=/scan,readonly}
      [ "$(cat "$source/repository/.secretlintrc.json")" = '{"rules":[{"id":"@secretlint/secretlint-rule-preset-recommend"}]}' ]
      [ "$(cat "$source/repository/content.txt")" = "staged" ]
      [ ! -e "$source/.secretlintrc.default.json" ]
      printf found >"$CONFIG_MARKER"
      ;;
  esac
done
`,
    );

    const result = run(hook, [], {
      cwd: root,
      env: hookEnvironment(root, {
        CONFIG_MARKER: marker,
        PATH: `${fakeBin}:${process.env.PATH}`,
      }),
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(marker, "utf8"), "found");
  });

  it("supplies the recommended configuration when the repository has none", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const capturedConfig = path.join(root, "captured-config");
    mkdirSync(fakeBin);
    writeFileSync(path.join(root, "content.txt"), "staged\n");
    git(root, "add", "content.txt");

    executable(
      path.join(fakeBin, "docker"),
      `#!/usr/bin/env bash
set -euo pipefail
mount=
config=
while [ "$#" -gt 0 ]; do
  case "$1" in
    type=bind,source=*,target=/scan,readonly) mount=$1 ;;
    --secretlintrc) shift; config=$1 ;;
  esac
  shift
done
[ "$config" = /scan/.secretlintrc.default.json ]
source=\${mount#type=bind,source=}
source=\${source%,target=/scan,readonly}
cp "$source/.secretlintrc.default.json" "$CAPTURED_CONFIG"
`,
    );

    const result = run(hook, [], {
      cwd: root,
      env: hookEnvironment(root, {
        CAPTURED_CONFIG: capturedConfig,
        PATH: `${fakeBin}:${process.env.PATH}`,
      }),
    });

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(readFileSync(capturedConfig, "utf8")), {
      rules: [{ id: "@secretlint/secretlint-rule-preset-recommend" }],
    });
  });

  it("distinguishes top-level package config from a nested secretlint key", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const marker = path.join(root, "default-config-used");
    mkdirSync(fakeBin);
    writeFileSync(
      path.join(root, "package.json"),
      '{"devDependencies":{"secretlint":"13.0.4"}}\n',
    );
    git(root, "add", "package.json");

    executable(
      path.join(fakeBin, "docker"),
      `#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" --secretlintrc /scan/.secretlintrc.default.json "*) config=default ;;
  *) config=package ;;
esac
[ "$config" = "$EXPECTED_CONFIG" ]
printf '%s' "$config" >"$CONFIG_MARKER"
`,
    );

    const result = run(hook, [], {
      cwd: root,
      env: hookEnvironment(root, {
        CONFIG_MARKER: marker,
        EXPECTED_CONFIG: "default",
        PATH: `${fakeBin}:${process.env.PATH}`,
      }),
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(marker, "utf8"), "default");

    writeFileSync(
      path.join(root, "package.json"),
      '{"secretlint":{"rules":[]},"devDependencies":{"secretlint":"13.0.4"}}\n',
    );
    git(root, "add", "package.json");
    const topLevelResult = run(hook, [], {
      cwd: root,
      env: hookEnvironment(root, {
        CONFIG_MARKER: marker,
        EXPECTED_CONFIG: "package",
        PATH: `${fakeBin}:${process.env.PATH}`,
      }),
    });

    assert.equal(topLevelResult.status, 0, topLevelResult.stderr);
    assert.equal(readFileSync(marker, "utf8"), "package");
  });

  it("is discovered by Git through the installed core.hooksPath", () => {
    const root = repository();
    const fakeBin = path.join(root, "fake-bin");
    const marker = path.join(root, "global-hook-ran");
    const env = hookEnvironment(root, {
      DOCKER_MARKER: marker,
      GIT_CONFIG_NOSYSTEM: "1",
      PATH: `${fakeBin}:${process.env.PATH}`,
    });
    mkdirSync(fakeBin);
    symlinkSync(repositoryRoot, path.join(env.HOME, ".dotfiles"), "dir");
    writeFileSync(
      path.join(env.HOME, ".gitconfig"),
      readFileSync(path.join(repositoryRoot, ".gitconfig")),
    );
    executable(
      path.join(fakeBin, "docker"),
      '#!/usr/bin/env bash\nprintf ran >"$DOCKER_MARKER"\n',
    );
    writeFileSync(path.join(root, "committed.txt"), "content\n");
    git(root, "add", "committed.txt");

    const result = run("git", ["commit", "--quiet", "-m", "exercise hook"], {
      cwd: root,
      env,
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(marker, "utf8"), "ran");
  });
});

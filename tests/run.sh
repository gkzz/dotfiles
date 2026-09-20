#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec mise --cd "$repository_root/.config/mise" exec -- \
  node --test --test-isolation=none --test-concurrency=1 \
  "$repository_root/tests/cli.test.mjs" \
  "$repository_root/tests/lifecycle.test.mjs" \
  "$repository_root/tests/packages.test.mjs" \
  "$repository_root/tests/resources.test.mjs" \
  "$repository_root/tests/shell-regression.test.mjs"

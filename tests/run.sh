#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec mise --cd "$repository_root/.config/mise" exec -- \
  node --test --test-isolation=none --test-concurrency=1 \
  "$repository_root/tests/bootstrap.test.js" \
  "$repository_root/tests/check.test.js" \
  "$repository_root/tests/cli.test.js" \
  "$repository_root/tests/helpers/fixture.test.js" \
  "$repository_root/tests/helpers/repository-config.test.js" \
  "$repository_root/tests/lifecycle.test.js" \
  "$repository_root/tests/packages.test.js" \
  "$repository_root/tests/symlinks.test.js"

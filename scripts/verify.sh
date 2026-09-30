#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ -f acceptance.sha256 ]]; then shasum -a 256 -c acceptance.sha256; fi
./script/build_and_run.sh --build-only
mkdir -p evidence
swift test 2>&1 | tee evidence/unit-tests.log
rg -q 'Executed ([3-9]|[1-9][0-9]+) tests, with 0 failures' evidence/unit-tests.log
if rg -i 'skipped|XCTSkip|failed \(' evidence/unit-tests.log; then exit 1; fi
test -x dist/Ashot.app/Contents/MacOS/Ashot
codesign --verify --strict dist/Ashot.app
BIN_DIR="$(swift build --show-bin-path)"
"$BIN_DIR/AshotOracle" compare fixtures/article.png fixtures/article.png
if [[ $# -gt 0 ]]; then "$BIN_DIR/AshotOracle" compare "$1" "${2:-fixtures/article.png}"; fi
echo 'VERIFY PASS (desktop acceptance is separately required)'

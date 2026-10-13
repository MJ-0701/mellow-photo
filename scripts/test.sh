#!/bin/bash
set -euo pipefail
MELLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MELLOW_ROOT"
MELLOW_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mellow-tests.XXXXXX")"
trap 'rm -rf "$MELLOW_TEST_DIR"' EXIT
swiftc -D ENGINE_STANDALONE Sources/MellowCore/Models.swift Sources/MellowCore/ImageEngine.swift Tests/MellowCoreTests/EngineTests.swift -o "$MELLOW_TEST_DIR/engine-tests"
"$MELLOW_TEST_DIR/engine-tests"

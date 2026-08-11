#!/bin/bash
#
# run-perft.sh — deep verification of the chess engine's move generator.
#
# Compiles Scan/Chess/*.swift plus Tools/perft-main.swift into an
# optimised command-line binary and checks every published perft count for
# the six standard test positions (~610M nodes, ~17s on Apple silicon).
#
# Why this exists as a separate binary rather than inside ScanTests:
#
#   * The XCTest suite runs against a **Debug** build, where this code is
#     ~20x slower. The full deep set would take about twelve minutes there
#     versus seventeen seconds here.
#   * `xcodebuild test` does not forward shell environment variables to the
#     test process, so the XCTSkipUnless gate on the deep tests cannot be
#     flipped from the command line — only from the scheme's Test action in
#     Xcode. This script needs no such plumbing.
#
# The fast subset of these counts *is* in ScanTests/ChessEngineTests.swift
# and runs on every `xcodebuild test`. This script is the pre-ship gate and
# the thing to run after any change to move generation.
#
# Usage:
#   Tools/run-perft.sh              # every position, every depth
#   Tools/run-perft.sh 4            # cap at depth 4 (a few seconds)
#   Tools/run-perft.sh divide "<fen>" <depth>
#                                   # per-move node counts, for debugging
#                                   # a mismatch against a reference engine
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chess_dir="$repo_root/Scan/Chess"
build_dir="${TMPDIR:-/tmp}/scan-perft"
binary="$build_dir/perft"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

mkdir -p "$build_dir"

# Rebuild only when a source file is newer than the binary. Keeps the
# debugging loop (`divide` after a failure) fast.
needs_build=0
if [[ ! -x "$binary" ]]; then
    needs_build=1
else
    while IFS= read -r source; do
        if [[ "$source" -nt "$binary" ]]; then needs_build=1; break; fi
    done < <(find "$chess_dir" -name '*.swift'; echo "$repo_root/Tools/perft/main.swift")
fi

if [[ $needs_build -eq 1 ]]; then
    echo "building perft…" >&2
    # -wmo so the optimiser can inline across the engine's files; without
    # it the bitboard helpers stay as real calls and throughput roughly
    # halves.
    # Scan/Chess/ is pure logic — Foundation and CoreGraphics only — which
    # is what lets this build outside Xcode. SwiftUI lives next door in
    # Scan/ChessUI/ and is deliberately not compiled here; if a new engine
    # file ever needs UIKit, it belongs in ChessUI, not in this build.
    xcrun swiftc -O -wmo -o "$binary" \
        "$repo_root/Tools/perft/main.swift" \
        "$chess_dir"/*.swift
fi

exec "$binary" "$@"

# ---------------------------------------------------------------------------
# If this script stops compiling, the usual cause is a new file in
# Scan/Chess/ that imports UIKit, SwiftUI, or app-level types like
# ScanSettingsKey. That directory is pure logic on purpose — Foundation,
# CoreGraphics, CoreImage and ImageIO only — because it is compiled here
# outside Xcode. UI belongs in Scan/ChessUI/; app policy belongs to the
# caller.

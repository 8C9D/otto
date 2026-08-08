#!/bin/bash
# Verifies the COMMITTED state of the repository - never the working tree.
#
# Wave 4's committed HEAD did not compile while the local tree passed, so a
# green local run is not evidence about the artifact. This script clones HEAD
# into a temp directory and proves, from scratch: xcodegen generates, every
# package's tests pass, the app target builds, and the tree lints clean under
# --strict. Run it before reporting any wave complete; report ITS numbers.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
WORKDIR="$(mktemp -d /tmp/otto-verify.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

CLONE="$WORKDIR/otto"

echo "== Otto verify: committed HEAD $HEAD_SHA"
echo "== Working tree state is deliberately ignored; only the clone is tested."
git clone --quiet "$REPO_ROOT" "$CLONE"
git -C "$CLONE" checkout --quiet "$HEAD_SHA"

# The package list is DERIVED from the clone, never hand-maintained: with a
# hand list a fourth package would be silently untested, and this script's one
# job is that nothing committed escapes it. Only directories carrying a
# Package.swift count. An empty derivation is a failure in its own right - a
# list that derives to nothing would let the loop below pass while testing
# nothing, the same class of defect as a guard that goes green while checking
# nothing.
PACKAGES=()
for manifest in "$CLONE"/Packages/*/Package.swift; do
    [[ -f "$manifest" ]] || continue
    PACKAGES+=("$(basename "$(dirname "$manifest")")")
done
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "!! no packages derived from Packages/ - refusing to pass on an empty list"
    exit 1
fi
echo "== packages (derived from the clone's Packages/): ${PACKAGES[*]}"

echo "== xcodegen generate"
(cd "$CLONE" && xcodegen generate --quiet)

# Sums every swift-testing run summary ("Test run with N tests ... passed")
# and the XCTest total ("Test Suite 'All tests' passed ... Executed N tests")
# from one log. Both frameworks can appear in a single `swift test` run.
count_tests() {
    local log="$1" swift_testing xctest
    swift_testing="$(grep -Eo 'Test run with [0-9]+ tests? in [0-9]+ suites? passed' "$log" \
        | grep -Eo '[0-9]+ tests?' | grep -Eo '[0-9]+' | paste -sd+ - || true)"
    xctest="$(awk "/Test Suite 'All tests' passed/{found=1} found && /Executed [0-9]+ tests?, with 0 failures/{print; exit}" "$log" \
        | grep -Eo 'Executed [0-9]+' | grep -Eo '[0-9]+' || true)"
    echo "$(( ${swift_testing:-0} + ${xctest:-0} ))"
}

declare -a COUNTS=()
TOTAL=0
for package in "${PACKAGES[@]}"; do
    echo "== swift test: $package"
    log="$WORKDIR/$package.log"
    if ! (cd "$CLONE" && swift test --package-path "Packages/$package" > "$log" 2>&1); then
        tail -n 40 "$log"
        echo "!! $package: TESTS FAILED (full log: $log preserved below)"
        cp "$log" "$REPO_ROOT/verify-$package-failure.log"
        echo "!! log copied to verify-$package-failure.log"
        exit 1
    fi
    count="$(count_tests "$log")"
    if [[ "$count" -eq 0 ]]; then
        echo "!! $package: reported 0 tests - the run passed but counted nothing, which is itself a failure"
        exit 1
    fi
    COUNTS+=("$package: $count")
    TOTAL=$((TOTAL + count))
done

echo "== xcodebuild: app target (simulator, unsigned)"
buildlog="$WORKDIR/xcodebuild.log"
if ! (cd "$CLONE" && xcodebuild build \
        -project Otto.xcodeproj \
        -scheme Otto \
        -destination 'generic/platform=iOS Simulator' \
        CODE_SIGNING_ALLOWED=NO > "$buildlog" 2>&1); then
    tail -n 40 "$buildlog"
    echo "!! app target: BUILD FAILED"
    exit 1
fi

echo "== swiftlint --strict"
(cd "$CLONE" && swiftlint --strict --quiet)

# The next-wave banner (spec §8, v2.5): 6B-Prep-3 sat correctly recorded in
# the spec's wave table and was still skipped for several sessions, because
# the table is not a surface anyone re-reads between waves. This run summary
# is - so the pointer lives here, and a missing or empty pointer fails the
# run. Deliberately NOT a claim that the named wave was done or that any wave
# was: this script cannot know, and a checklist that lies is worse than none.
NEXT_WAVE_FILE="$CLONE/docs/next-wave.md"
if [[ ! -s "$NEXT_WAVE_FILE" ]]; then
    echo "!! docs/next-wave.md is missing or empty - every wave's closing session"
    echo "!! must leave a pointer to the next one (see README: Verifying a wave)"
    exit 1
fi

echo
echo "== VERIFIED: $HEAD_SHA builds, tests, and lints from a clean clone"
for line in "${COUNTS[@]}"; do
    echo "   $line"
done
echo "   total: $TOTAL tests"
echo
echo "   NOT counted: the OttoUI Dynamic Type suite is UIKit-hosted and compiles"
echo "   to nothing under swift test on a mac host. It runs only on a simulator"
echo "   (the CI simulator job, or xcodebuild test locally) - do not report its"
echo "   tests as covered by this script's total."
echo
echo "== NEXT WAVE (docs/next-wave.md - update it as part of landing a wave):"
sed 's/^/   /' "$NEXT_WAVE_FILE"

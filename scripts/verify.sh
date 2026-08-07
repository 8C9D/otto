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
PACKAGES=(OttoDomain OttoPersistence OttoUI)

echo "== Otto verify: committed HEAD $HEAD_SHA"
echo "== Working tree state is deliberately ignored; only the clone is tested."
git clone --quiet "$REPO_ROOT" "$CLONE"
git -C "$CLONE" checkout --quiet "$HEAD_SHA"

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

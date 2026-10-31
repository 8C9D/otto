#!/bin/bash
# Runs SyncLifecycleUITests: the real app, through the real UI, on a real
# mirrored store, on a simulator created for the run and deleted after it.
#
# The test cannot set any of this up for itself. It needs a simulator with no
# iCloud account (a fresh one has none), an ad-hoc signed build, because an
# unsigned one carries no iCloud entitlement and the mirrored store would never
# start, and a backup file in the app's Documents for the import steps.
#
# Usage: scripts/sync-lifecycle.sh [runs]
# Each run starts from a fresh install. Tests the working tree, unlike verify.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS="${1:-1}"
BUNDLE_ID="com.arthurzhang.otto"
# CI names the directory so it can upload a failed run's result bundle.
WORKDIR="${LIFECYCLE_WORKDIR:-$(mktemp -d /tmp/otto-lifecycle.XXXXXX)}"
mkdir -p "$WORKDIR"
UDID=""
PASSED="no"
NOT_EXERCISED="no"

cleanup() {
    if [[ -n "$UDID" ]]; then
        xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
        xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
    fi
    # A failed run keeps its logs and result bundle: they are the only record
    # of what the screen showed.
    if [[ "$PASSED" == "yes" ]]; then
        rm -rf "$WORKDIR"
    else
        echo "!! kept for inspection: $WORKDIR"
    fi
}
trap cleanup EXIT

# Newest available iOS runtime, and the first iPhone it supports. Derived, so a
# runner image changing its simulators cannot skip this: nothing found fails.
read -r RUNTIME DEVICE_TYPE < <(xcrun simctl list --json | python3 -c '
import json, sys
catalog = json.load(sys.stdin)
runtimes = [r for r in catalog["runtimes"] if r["isAvailable"] and r["platform"] == "iOS"]
runtime = max(runtimes, key=lambda r: [int(part) for part in r["version"].split(".")])
device = next(d for d in runtime["supportedDeviceTypes"] if d["productFamily"] == "iPhone")
print(runtime["identifier"], device["identifier"])
')
UDID="$(xcrun simctl create OttoLifecycle "$DEVICE_TYPE" "$RUNTIME")"
echo "== simulator $UDID ($RUNTIME)"

SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
XCODE=(-project Otto.xcodeproj -scheme Otto -configuration Debug
       -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$WORKDIR/build")

cd "$REPO_ROOT"
xcodegen generate --quiet
echo "== build"
if ! xcodebuild build-for-testing "${XCODE[@]}" "${SIGNING[@]}" > "$WORKDIR/build.log" 2>&1; then
    tail -n 40 "$WORKDIR/build.log"
    echo "!! build failed"
    exit 1
fi

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b > /dev/null

# An empty but valid export: the import steps are about whether a restore is
# allowed to run, and an empty file leaves the store's data as the only variable.
cat > "$WORKDIR/sync-lifecycle-backup.json" <<'JSON'
{"formatVersion":4,"exportedAt":"2026-10-31T12:00:00.000Z","subscriptions":[],"paymentMethods":[],"billingEvents":[],"cancellationEpisodes":[],"priceChanges":[]}
JSON

for run in $(seq 1 "$RUNS"); do
    echo "== run $run of $RUNS"
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
    xcrun simctl uninstall "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
    xcrun simctl install "$UDID" "$WORKDIR/build/Build/Products/Debug-iphonesimulator/Otto.app"
    documents="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Documents"
    mkdir -p "$documents"
    cp "$WORKDIR/sync-lifecycle-backup.json" "$documents/"

    log="$WORKDIR/run-$run.log"
    if ! xcodebuild test-without-building "${XCODE[@]}" \
            -resultBundlePath "$WORKDIR/run-$run.xcresult" > "$log" 2>&1; then
        grep -E 'error:|Test Case.*failed' "$log" | tail -n 20 || tail -n 40 "$log"
        echo "!! run $run failed"
        exit 1
    fi
    grep -E "Test Case.*passed" "$log" || true
    # A green run must not claim more than it did. On a CPU-starved host the
    # system picker can stop answering, and the import steps behind it are
    # reported rather than failed (see `pick` in the test).
    if grep -q 'LIFECYCLE-PICKER-UNRESPONSIVE' "$log"; then
        NOT_EXERCISED="yes"
        echo "!! run $run: the system picker did not respond, so an import step did not run"
    fi
done

PASSED="yes"
echo "== VERIFIED: $RUNS of $RUNS sync lifecycle runs passed"
if [[ "$NOT_EXERCISED" == "yes" ]]; then
    message="NOT exercised: at least one import through the system picker. The restore refusal stays pinned by SyncPrerequisiteTests."
    echo "   $message"
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::warning title=Sync lifecycle::$message"
    fi
fi

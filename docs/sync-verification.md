# Sync verification - Wave 6B

**What this is:** the runbook for the part of Wave 6B that cannot be done on one Mac: proving sync against a real CloudKit container.
**Standard:** spec §9b. *A subsystem reporting that it accepted your work is evidence about the subsystem, never about your code.* A step passes on what the device shows, never on CloudKit Console saying it took the records.

Nothing here has been run yet. Until it has, sync is code that opens correctly, not a feature. Release builds stay off (`OTTO_CLOUDKIT_CONTAINER` is empty) so nothing reaches production by accident.

## Already verified, without iCloud

Real app, real `NSCloudKitMirroringDelegate`, simulator with no iCloud account, through the real UI. `scripts/sync-lifecycle.sh` reruns all of it, and CI does on every PR:

| Claim | Evidence |
|---|---|
| The V3 store opens mirrored | `ANSCK*` tables created; setup reports `CKAccountStatusNoAccount`, the expected refusal |
| Local data survives local → mirrored → local → mirrored | Row present in the store and on screen after each launch |
| A once-mirrored store reopens locally | The kill-switch path, launched for real |
| Framework events reach Otto under SwiftData | `[sync] setup failed: accountUnavailable` |
| Restore refuses in a mirrored session, runs once stopped (§8 4a) | `import FAILED - nothing was applied`, then `import end`, through the real file picker. On a quiet machine: on a CPU-starved host the system picker can stop responding, and the script says when these steps did not run |
| The purge makes a real `CKDatabase` call and reports failure | `cloud call failed: 9`; state unchanged |
| The enable flow refuses with no account | Real `accountStatus()`; no flag, no snapshot |

**Not covered by any of that:** a single record ever leaving the device.

## Setup

You need two devices **on the same Apple Account**. The second user's phone does not count: each account has its own private database, so her phone can never see yours. The owner's chosen pair is the iPhone plus a simulator signed into the same account.

Use Debug builds from Xcode: they reach the CloudKit **Development** environment, which can be reset. TestFlight reaches Production, which cannot.

Watch each device with:

```sh
log stream --device --predicate 'subsystem == "com.arthurzhang.otto" AND category == "sync"'
```

or filter Xcode's console on `[sync]`. Device logs carry opaque ids and counts only.

Use throwaway subscriptions. Export a backup from your real data first.

## Steps

**1. Initialize the schema.** Run a Debug build, signed into iCloud, with launch argument `-OttoInitializeCloudKitSchema`. Pass: CloudKit Console's Development schema lists all eight `CD_Stored…` record types. This is not optional: without it, a field that happened to be nil everywhere never reaches the schema, and Production rejects it the first time it has a value.

**2. First device.** Settings → Turn On iCloud Sync. Pass: the backup is in Files; the row reads "Starts next launch"; after reopening, `import succeeded` and `export succeeded` appear and the row reads "Up to date".

**3. Join.** Fresh install on device B; turn on sync before adding anything; reopen. Pass: Today shows "Getting your subscriptions from iCloud" rather than "No subscriptions yet"; then every subscription, charge and pause appears; `converged` is logged; `pass begin trigger=cloudSync` is logged; reminders match device A.

**4. Edits, both ways.** Rename, change a price, pause, cancel, delete, each on one device. Pass: the other device shows it without being reopened, and its pending reminders follow.

**5. Conflicts.** Airplane mode on both, then on each: pause the same subscription; on another, cancel; on a third, let a new charge date pass so both materialize it. Reconnect. Pass: both devices end identical; one open pause; one open cancellation; one ledger row per date; `converged ledger=… cancellations=…` is non-zero once, then zero; the logs stop (no ping-pong).

**6. Reinstall - the reason sync exists.** On a device with charges history: delete the app. Wait until a charge date has passed, or set up a subscription whose date falls in the gap. Reinstall, turn on sync, reopen. Pass: everything returns, **and the charge from the gap has a row**. This is the founding hazard reached through iCloud.

**7. Join rule.** On a device with local data, while iCloud has a copy: turn on sync. Pass: refused with the "already has Otto data" message; no flag set.

**8. Kill switch.** Stop Syncing; reopen. Pass: "Stopped"; edit something here and on the other device. Neither crosses. Resume; reopen. Pass: **both edits arrive**. The Stopped footer promises this and it has not been observed; if it fails, change the footer before anything else.

**9. Restore.** While syncing, import a backup. Pass: refused. Stop, reopen, import, resume, reopen. Pass: the restored state reaches the other device as ordinary edits; no mass disappearance.

**10. Purge.** Stop on every device, reopen, delete the iCloud copy. Pass: the zone is gone from Console, and this device keeps its data and reads "Off". **Then record what the other device does when it resumes.** The spec says a purge deletes nothing on any device; forum reports describe a full mirroring reset, with local rows surviving in at least one. Unobserved here. This is §8's "must be tested against a real container".

**11. Sign-out.** Sign out of iCloud on device B (or turn iCloud off for Otto). Expected, by Apple's design: the framework clears synced records from the device. Pass: Today shows "iCloud is signed out" rather than "No subscriptions yet". Record whether pending reminders were removed. Sign back in. Pass: data returns. Then make an edit in airplane mode, sign out before it uploads, and record what is lost: Apple's forums describe this as lost by design, and users should hear that from us.

## Before production

Only after every step above passes. Field-level encryption is already decided: V3 deploys as it is (`DECISIONS.md`, "Encrypted fields").

1. **Deploy the schema** in CloudKit Console. Permanent: Production record types and fields can never be removed, and a deployed field can never become encrypted.
2. Set `OTTO_CLOUDKIT_CONTAINER` for Release in `project.yml`.
3. Repeat steps 2-4 on TestFlight builds, against Production.

Next wave: **6B - CloudKit activation**, specified in `docs/Subscription-Tracker-Spec.md` §8 (v2.6), gated on the manual checks in `docs/cloudkit-readiness.md`.
Wave 10 (Notification Delivery & Check-Date Fixes, from the Aug 2026 device run) landed in between; 6B remains the next planned wave.
Carry-over candidates for a later wave: simulator-hosted `NotificationCoordinator` tests (see `docs/implementation-notes/wave-10.md`, "Deliberately not done").

Gate 1 (Aug 2026) landed the GitHub remote and the first CI run; see `DECISIONS.md`, "Gate 1".
Standing consequence for every later wave: **CI, not `verify.sh`, is now the gate.**
`verify.sh` clones the committed code into the same locale on the same hardware, so it cannot see a host-environment dependency - which is exactly what CI's first run found twice.
Gate 2 (`BGAppRefreshTask`) is **met** as of Aug 2026: the handler was observed executing on device in both Debug and Release after a one-line isolation fix, having crashed on every attempt before it.
Fixing the crash exposed a second defect it had been hiding - expiration completed the task while the pass ran on and completed it again - and that is fixed too (§9a), with both a completion latch and real cancellation checkpoints.
Carry into 6B: **a subsystem reporting that it accepted your work is evidence about the subsystem, never about your code.** `dasd` scheduled the dead background task for months; CloudKit's acknowledgements will be exactly as reassuring.
One device gate remains: data surviving delete-and-reinstall.

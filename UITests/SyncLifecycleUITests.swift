import XCTest

/// The real app, through the real UI, on a real mirrored store: the one layer
/// where a released event monitor silently disabled all of sync while every
/// unit test passed (`DECISIONS.md`, Wave 6B).
///
/// Run it with `scripts/sync-lifecycle.sh`, not from Xcode. The script supplies
/// what this test cannot give itself: a fresh simulator with no iCloud account,
/// an ad-hoc signed build that carries the iCloud entitlement, and a backup
/// file seeded into the app's Documents.
///
/// **What this proves is everything short of iCloud.** With no account, no
/// record leaves the device, so "synced" appears nowhere below;
/// `docs/sync-verification.md` covers that half.
///
/// One test, in order, because each launch inherits the store the last one
/// left: surviving those transitions is what is under test.
final class SyncLifecycleUITests: XCTestCase {
    private let subscriptionName = "Lifecycle Netflix"
    private let backupFileName = "sync-lifecycle-backup"
    private let mergeTitle = "Merge - keep both, newer copy wins"
    /// `-sync.enabled` lands in the argument domain, so a launch opens mirrored
    /// without an iCloud account the enable flow would refuse.
    private let mirroredArguments = ["-sync.enabled", "YES"]
    /// Generous because a CI runner's CloudKit client can take its time, and a
    /// wait only ever costs this long when something is already wrong.
    private let patience: TimeInterval = 30

    override func setUp() {
        continueAfterFailure = false
    }

    func testSyncLifecycle() {
        // A device starts local, and with no account it stays that way.
        var app = launch([])
        enableIsRefusedWithoutAnAccount(app)
        addSubscription(app)
        app.terminate()

        // The same store, opened mirrored. §8 4a: a restore here must refuse.
        app = launch(mirroredArguments)
        mirroredStoreKeepsItsData(app)
        if importBackup(app) {
            expectAlert("Nothing was imported", app)
        }
        stopSyncing(app)
        app.terminate()

        // A once-mirrored store, opened locally: what the kill switch does.
        app = launch(mirroredArguments)
        stoppedStoreKeepsItsData(app)
        if importBackup(app) {
            expectAlert("Import complete", app)
        }
        subscriptionIsListed(app)
        purgeFailsSafelyWithoutAnAccount(app)
        resumeSyncing(app)
        app.terminate()

        // Back to mirrored over the same data.
        app = launch(mirroredArguments)
        settingsStatus("Signed out", app)
        subscriptionIsListed(app)
    }

    // MARK: - Steps

    private func enableIsRefusedWithoutAnAccount(_ app: XCUIApplication) {
        tab("Settings", app)
        let turnOn = app.buttons["Turn On iCloud Sync…"]
        reveal(turnOn, app)
        turnOn.tap()
        confirm("Back Up and Turn On", app)
        // The real `CKContainer` account check, not a fake.
        expectAlert("iCloud sync", app)
        reveal(turnOn, app)
    }

    private func addSubscription(_ app: XCUIApplication) {
        tab("Subscriptions", app)
        app.buttons["Add Subscription"].firstMatch.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: patience))
        name.tap()
        name.typeText(subscriptionName)
        let price = app.textFields["Price"]
        price.tap()
        price.typeText("20.99")
        app.buttons["Save"].tap()
        subscriptionIsListed(app)
    }

    private func mirroredStoreKeepsItsData(_ app: XCUIApplication) {
        tab("Today", app)
        XCTAssertTrue(app.staticTexts["iCloud is signed out"].waitForExistence(timeout: patience))
        subscriptionIsListed(app)
        settingsStatus("Signed out", app)
    }

    private func stopSyncing(_ app: XCUIApplication) {
        let stop = app.buttons["Stop Syncing…"]
        reveal(stop, app)
        stop.tap()
        confirm("Stop Syncing", app)
        settingsStatus("Stops next launch", app)
        // Still mirroring until the next launch: a purge now would recreate
        // the zone it deleted.
        XCTAssertFalse(app.buttons["Delete Copy from iCloud…"].exists)
    }

    private func stoppedStoreKeepsItsData(_ app: XCUIApplication) {
        settingsStatus("Stopped", app)
        subscriptionIsListed(app)
        tab("Today", app)
        XCTAssertFalse(app.staticTexts["iCloud is signed out"].exists)
    }

    private func purgeFailsSafelyWithoutAnAccount(_ app: XCUIApplication) {
        tab("Settings", app)
        let delete = app.buttons["Delete Copy from iCloud…"]
        reveal(delete, app)
        delete.tap()
        confirm("Delete from iCloud", app)
        // A real `CKDatabase` call, answered `notAuthenticated`.
        expectAlert("iCloud sync", app)
        settingsStatus("Stopped", app)
    }

    private func resumeSyncing(_ app: XCUIApplication) {
        let resume = app.buttons["Resume Syncing"]
        reveal(resume, app)
        resume.tap()
        settingsStatus("Starts next launch", app)
    }

    /// Through the real document picker, to the file the script seeded. Returns
    /// whether the import ran, so the caller only asserts on one that did.
    private func importBackup(_ app: XCUIApplication) -> Bool {
        tab("Settings", app)
        let button = app.buttons["Import from a backup…"]
        reveal(button, app)
        button.tap()
        let file = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", backupFileName)).firstMatch
        if !file.waitForExistence(timeout: 6) {
            for location in ["Browse", "On My iPhone", "Otto"] {
                let target = app.descendants(matching: .any)[location].firstMatch
                if target.waitForExistence(timeout: 4) { target.tap() }
            }
        }
        XCTAssertTrue(file.waitForExistence(timeout: patience), "the seeded backup never reached the picker")
        guard pick(file, app) else { return false }
        confirm(mergeTitle, app)
        return true
    }

    /// Returns false when the system picker never responded to the file.
    ///
    /// **That is the host, not Otto.** The picker runs in another process, and
    /// on a CPU-starved host it stops answering file selection while its own
    /// navigation and close button keep working: 0 of 9 picks under load across
    /// tap styles, 0 of 2 with a 200 s wait, against 30 of 30 on a quiet machine.
    /// So it is reported, and the steps behind it do not run, the same treatment
    /// `DECISIONS.md` gives an accessibility tree with no client: never silently
    /// skipped, and never able to turn the job red for a reason that is not
    /// about the app. The script prints what this run did not exercise.
    ///
    /// A picker that CLOSES with no prompt is the opposite case: Otto dropped its
    /// own dialog, a user-visible bug, and it fails as exactly that.
    private func pick(_ file: XCUIElement, _ app: XCUIApplication) -> Bool {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: file)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: patience), .completed, "the file never became tappable")
        file.tap()
        if app.buttons[mergeTitle].waitForExistence(timeout: patience) { return true }
        XCTAssertTrue(file.exists, "the picker closed and no prompt appeared")
        // No screenshot here: XCTest records the screen anyway, and asking for
        // one on a starved host times out and fails the test by itself.
        NSLog("LIFECYCLE-PICKER-UNRESPONSIVE")
        app.buttons["Cancel"].firstMatch.tap()
        return false
    }

    // MARK: - Helpers

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func tab(_ title: String, _ app: XCUIApplication) {
        app.tabBars.buttons[title].firstMatch.tap()
    }

    private func confirm(_ title: String, _ app: XCUIApplication) {
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: patience), "no \(title) button")
        button.tap()
    }

    private func expectAlert(_ title: String, _ app: XCUIApplication) {
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: patience), "no \(title) alert")
        alert.buttons["OK"].tap()
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists, "missing: \(element)")
    }

    /// `LabeledContent` reads as one combined accessibility label.
    private func settingsStatus(_ value: String, _ app: XCUIApplication) {
        tab("Settings", app)
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", "iCloud sync, \(value)")).firstMatch
        reveal(row, app)
    }

    private func subscriptionIsListed(_ app: XCUIApplication) {
        tab("Subscriptions", app)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", subscriptionName)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: patience), "the subscription did not survive")
    }
}

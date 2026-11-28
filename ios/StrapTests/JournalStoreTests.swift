import XCTest
@testable import Strap

/// Uses a unique UserDefaults suite per test so the real journal is never touched.
final class JournalStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: JournalStore!

    override func setUp() {
        super.setUp()
        suiteName = "strap.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = JournalStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    func testQuestionVisibilityPreservesAnswers() {
        var entry = JournalEntry(dateKey: "2026-11-09")
        entry.setAnswer(.alcohol, true)
        store.save(entry)
        let hidden = JournalQuestionPreferences.setting(.alcohol, visible: false, in: "")
        XCTAssertFalse(JournalQuestionPreferences.visible(excluding: hidden).contains(.alcohol))
        XCTAssertEqual(store.entry(forDayKey: entry.dateKey)?.answer(.alcohol), true)
        XCTAssertEqual(JournalQuestionPreferences.setting(.alcohol, visible: true, in: hidden), "")
        XCTAssertEqual(JournalQuestionPreferences.visible(excluding: "").count, JournalQuestion.allCases.count)
    }

    func testSaveAndReadBack() {
        var entry = JournalEntry(dateKey: "2026-11-09")
        entry.setAnswer(.alcohol, true)
        entry.setAnswer(.lateCaffeine, true)
        entry.mood = .good
        entry.soreness = .mild
        entry.notes = "Race tomorrow."
        store.save(entry)

        let loaded = store.entry(forDayKey: "2026-11-09")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded, entry)
        XCTAssertEqual(loaded?.yesCount, 2)
        XCTAssertEqual(loaded?.mood, .good)
        XCTAssertEqual(loaded?.soreness, .mild)
        XCTAssertEqual(loaded?.notes, "Race tomorrow.")
    }

    func testSavingAgainUpdatesTheSameDay() {
        var entry = JournalEntry(dateKey: "2026-11-09")
        entry.setAnswer(.travel, true)
        entry.mood = .okay
        store.save(entry)

        var updated = entry
        updated.setAnswer(.travel, false)
        updated.setAnswer(.illnessFeel, true)
        updated.mood = .low
        updated.notes = "Updated later that day."
        store.save(updated)

        XCTAssertEqual(store.allEntries().count, 1, "One entry per day — saving again must update, not duplicate")
        let loaded = store.entry(forDayKey: "2026-11-09")
        XCTAssertEqual(loaded, updated)
        XCTAssertEqual(loaded?.answer(.travel), false)
        XCTAssertEqual(loaded?.answer(.illnessFeel), true)
        XCTAssertEqual(loaded?.mood, .low)
    }

    func testDifferentDaysAreSeparateEntries() {
        store.save(JournalEntry(dateKey: "2026-11-08"))
        var second = JournalEntry(dateKey: "2026-11-09")
        second.setAnswer(.lateMeal, true)
        store.save(second)

        XCTAssertEqual(store.allEntries().count, 2)
        XCTAssertEqual(store.entry(forDayKey: "2026-11-08")?.yesCount, 0)
        XCTAssertEqual(store.entry(forDayKey: "2026-11-09")?.yesCount, 1)
        XCTAssertNil(store.entry(forDayKey: "2026-11-10"))
    }

    func testUnansweredQuestionsDefaultToNo() {
        let entry = JournalEntry(dateKey: "2026-11-09")
        for question in JournalQuestion.allCases {
            XCTAssertFalse(entry.answer(question), "\(question.label) must default to No")
        }
        XCTAssertEqual(entry.yesCount, 0)
        XCTAssertNil(entry.mood)
        XCTAssertEqual(entry.soreness, .none)
        XCTAssertEqual(JournalQuestion.allCases.count, 7)
    }

    func testPersistenceAcrossStoreInstances() {
        var entry = JournalEntry(dateKey: "2026-11-09")
        entry.mood = .great
        store.save(entry)

        let reloaded = JournalStore(defaults: defaults)
        XCTAssertEqual(reloaded.entry(forDayKey: "2026-11-09"), entry)
    }

    func testDayKeyFormat() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = 9
        parts.hour = 23
        parts.minute = 59
        guard let date = Calendar.current.date(from: parts) else {
            return XCTFail("Could not build test date")
        }
        XCTAssertEqual(JournalStore.dayKey(for: date), "2026-11-09")
        XCTAssertEqual(store.entry(on: date)?.dateKey, nil)
    }

    func testEntryOnDateRoundTrip() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = 9
        parts.hour = 8
        guard let date = Calendar.current.date(from: parts) else {
            return XCTFail("Could not build test date")
        }
        let entry = JournalEntry(dateKey: JournalStore.dayKey(for: date))
        store.save(entry)
        XCTAssertEqual(store.entry(on: date), entry)
    }

    func testSleepLifecyclePersistsAndDoesNotRepeatJournal() {
        let persistence = SleepLifecyclePersistence(defaults: defaults)
        var state = persistence.load()
        XCTAssertEqual(state.phase, .idle)
        state.confirm(sessionID: "night-1", startUnix: 1000)
        state.confirm(sessionID: "night-2", startUnix: 1200)
        XCTAssertEqual(state.sessionID, "night-1")
        state.end(sessionID: "night-2", at: 2000)
        XCTAssertEqual(state.phase, .detected)
        state.end(sessionID: "night-1", at: 2000)
        state.end(sessionID: "night-1", at: 3000)
        XCTAssertEqual(state.endedAtUnix, 2000)
        state.finishProcessing(sessionID: "night-1", hasJournalQuestions: true)
        persistence.save(state)
        var restored = persistence.load()
        XCTAssertEqual(restored.phase, .journalPending)
        restored.acknowledgeJournal(sessionID: "night-1")
        restored.acknowledgeJournal(sessionID: "night-1")
        XCTAssertEqual(restored.phase, .completed)
        XCTAssertTrue(restored.journalPresented)
        persistence.save(restored)
        XCTAssertEqual(persistence.load(), restored)
    }

    func testProvisionalWakeSurvivesRelaunchAndRejoinsTheSameNight() {
        let persistence = SleepLifecyclePersistence(defaults: defaults)
        var state = SleepLifecycleSnapshot()
        state.confirm(sessionID: "100-4300", startUnix: 100)
        state.observeProvisionalWake(sessionID: "100-4300")
        persistence.save(state)
        state = persistence.load()
        XCTAssertEqual(state.phase, .provisionalWake)
        XCTAssertNil(state.endedAtUnix)

        let resumed = SleepPeriod(startUnix: 90, endUnix: 5499, quietFraction: 0.9,
                                  meanHR: 60, wakeEvents: 1)
        XCTAssertTrue(state.reconcileDetectedWindow(resumed, id: "90-5500"))
        state.resume(sessionID: "90-5500")
        XCTAssertEqual(state.phase, .detected)
        state.observeProvisionalWake(sessionID: "90-5500")
        state.end(sessionID: "90-5500", at: 5500)
        state.finishProcessing(sessionID: "90-5500", hasJournalQuestions: true)
        XCTAssertEqual(state.phase, .journalPending)
        XCTAssertEqual(state.endedAtUnix, 5500)
    }

    func testExplicitEndCompletesUnderTheSavedWindowIdentity() {
        var state = SleepLifecycleSnapshot()
        state.confirm(sessionID: "100-4300", startUnix: 100)
        state.end(sessionID: "100-4300", at: 4350, resultingSessionID: "100-4350")
        XCTAssertEqual(state.phase, .processing)
        state.finishProcessing(sessionID: "100-4300", hasJournalQuestions: true)
        XCTAssertEqual(state.phase, .processing)
        state.finishProcessing(sessionID: "100-4350", hasJournalQuestions: true)
        XCTAssertEqual(state.phase, .journalPending)
        XCTAssertEqual(state.endedAtUnix, 4350)
    }

    func testSleepLifecycleRejectsCompletedSessionReplayAndOverlappingHistory() {
        let persistence = SleepLifecyclePersistence(defaults: defaults)
        var state = persistence.load()
        state.confirm(sessionID: "night-1", startUnix: 1000)
        state.end(sessionID: "night-1", at: 2000)
        state.finishProcessing(sessionID: "night-1", hasJournalQuestions: false)
        persistence.save(state)
        state = persistence.load()
        let completed = state
        state.confirm(sessionID: "night-1", startUnix: 1000)
        XCTAssertEqual(state, completed)
        state.confirm(sessionID: "reindexed-night", startUnix: 1500)
        XCTAssertEqual(state, completed)
        state.confirm(sessionID: "night-2", startUnix: 3000)
        XCTAssertEqual(state.phase, .detected)
        XCTAssertEqual(state.sessionID, "night-2")
    }

    func testSleepLifecycleRejectsUnconfirmedAndInvalidTransitions() {
        var state = SleepLifecycleSnapshot()
        state.end(sessionID: "unknown", at: 2000)
        XCTAssertEqual(state.phase, .idle)
        state.confirm(sessionID: "", startUnix: 1000)
        XCTAssertEqual(state.phase, .idle)
        state.confirm(sessionID: "night", startUnix: 1000)
        state.end(sessionID: "night", at: 1000)
        XCTAssertEqual(state.phase, .detected)
        state.finishProcessing(sessionID: "night", hasJournalQuestions: true)
        XCTAssertEqual(state.phase, .detected)
        state.end(sessionID: "night", at: 1500)
        state.finishProcessing(sessionID: "night", hasJournalQuestions: false)
        XCTAssertEqual(state.phase, .completed)
    }

    func testAppStoreInitializesSleepLifecycleAndAcknowledgesJournal() {
        let persistence = SleepLifecyclePersistence(defaults: defaults)
        var state = persistence.load()
        state.confirm(sessionID: "active-night", startUnix: 5000)
        state.end(sessionID: "active-night", at: 6000)
        state.finishProcessing(sessionID: "active-night", hasJournalQuestions: true)
        persistence.save(state)

        let store = AppStore(defaults: defaults)
        XCTAssertEqual(store.sleepLifecycle.phase, .journalPending)
        XCTAssertEqual(store.sleepLifecycle.sessionID, "active-night")

        store.acknowledgeSleepJournal()
        XCTAssertEqual(store.sleepLifecycle.phase, .completed)
        XCTAssertTrue(store.sleepLifecycle.journalPresented)
    }

}
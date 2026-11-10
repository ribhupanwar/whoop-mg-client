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
}
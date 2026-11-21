import UIKit
import XCTest
@testable import Strap

final class ActivityIconRegistryTests: XCTestCase {
    func testMappedLegacySportIDsSelectTheirEstablishedActivityKind() {
        let expected: [(Int, ActivityKind)] = [
            (0, .run),
            (1, .cycling),
            (16, .baseball),
            (17, .basketball),
            (18, .rowing),
            (19, .fencing),
            (20, .hockey),
            (21, .football),
            (22, .golf),
            (24, .hockey),
            (25, .lacrosse),
            (27, .rugby),
            (29, .skiing),
            (30, .soccer),
            (31, .softball),
            (32, .squash),
            (33, .swimming),
            (34, .tennis),
            (36, .volleyball),
            (38, .wrestling),
            (39, .boxing),
            (42, .dance),
            (43, .pilates),
            (44, .yoga),
            (45, .weightlifting),
            (48, .functionalFitness),
            (51, .gymnastics),
            (52, .hiking),
            (53, .horsebackRiding),
            (55, .kayaking),
            (56, .martialArts),
            (60, .climbing),
            (61, .paddleboarding),
            (63, .walk),
            (64, .surfing),
            (65, .elliptical),
            (66, .stairClimber),
            (70, .meditation),
            (71, .other),
            (84, .jumpRope),
            (96, .hiit),
            (97, .spin),
            (100, .cricket),
            (101, .pickleball),
            (102, .skating),
            (107, .barre),
            (123, .strengthTraining),
            (128, .stretching),
            (230, .tableTennis),
            (231, .badminton),
            (235, .gardening),
            (239, .skating),
            (240, .handball),
        ]
        for (id, kind) in expected {
            let selected = ActivityIconRegistry.importedKind(sportID: id, sportName: "")
            XCTAssertEqual(selected, kind, "Sport ID \(id)")
            XCTAssertNotNil(UIImage(systemName: selected.icon), selected.icon)
        }
    }

    func testPresentationDistinguishesActivitiesAndUsesAnUnknownFallback() {
        let kinds: [ActivityKind] = [.run, .walk, .weightlifting, .strengthTraining, .other]
        XCTAssertEqual(Set(kinds.map(\.icon)).count, kinds.count)
        XCTAssertEqual(ActivityIconRegistry.detectedIcon("run"), ActivityKind.run.icon)
        XCTAssertEqual(ActivityIconRegistry.detectedIcon("walk"), ActivityKind.walk.icon)
        XCTAssertEqual(ActivityIconRegistry.detectedIcon("unknown"), ActivityKind.other.icon)
        XCTAssertEqual(ActivityIconRegistry.importedKind(sportID: nil, sportName: "strength_trainer"), .strengthTraining)
        XCTAssertEqual(ActivityIconRegistry.importedKind(sportID: 999_999, sportName: "running"), .other)
        XCTAssertNotNil(UIImage(systemName: ActivityIconRegistry.sleep))
        XCTAssertNotNil(UIImage(systemName: ActivityIconRegistry.nap))
    }

    func testHistoryPreservesUnknownIDAcrossImportRoundTripAndRefresh() throws {
        let name = "ActivityIconRegistryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ActivityStore(defaults: defaults)
        let oldPage = Data("""
        {"records":[{"id":"legacy","sport_name":"private activity","sport_id":999999,
        "start":"2026-11-20T10:00:00Z","end":"2026-11-20T10:05:00Z"}]}
        """.utf8)
        let newPage = Data("""
        {"records":[{"id":"legacy","sport_name":"private activity",
        "start":"2026-11-20T10:00:00Z","end":"2026-11-20T10:06:00Z"}]}
        """.utf8)
        store.mergeWhoopWorkouts(try WhoopWorkoutImport.decodePage(oldPage).workouts)
        store.mergeWhoopWorkouts(try WhoopWorkoutImport.decodePage(newPage).workouts)
        let saved = try XCTUnwrap(store.whoopWorkouts().first)
        XCTAssertEqual(saved.sportID, 999_999)
        XCTAssertEqual(saved.sportName, "private activity")
        XCTAssertEqual(saved.endUnix - saved.startUnix, 360)
        XCTAssertEqual(saved.activityIcon, ActivityKind.other.icon)

        let olderSavedRecord = Data("""
        {"id":"older","sportName":"running","startUnix":100,"endUnix":160}
        """.utf8)
        let older = try JSONDecoder().decode(WhoopWorkout.self, from: olderSavedRecord)
        XCTAssertNil(older.sportID)
        XCTAssertEqual(older.activityIcon, ActivityKind.run.icon)
    }

    func testCurrentWorkoutNameDoesNotGetOverriddenByKnownLegacyID() throws {
        let name = "ActivityIconRegistryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ActivityStore(defaults: defaults)
        let old = WhoopWorkout(id: "edited", sportName: "running", startUnix: 100, endUnix: 160,
                               strain: nil, averageHeartRate: nil, sportID: 0)
        let renamed = WhoopWorkout(id: "edited", sportName: "cycling", startUnix: 100, endUnix: 160,
                                   strain: nil, averageHeartRate: nil)
        store.mergeWhoopWorkouts([old, renamed])
        let saved = try XCTUnwrap(store.whoopWorkouts().first)
        XCTAssertEqual(saved.sportID, 0)
        XCTAssertEqual(saved.activityIcon, ActivityKind.cycling.icon)

        var explicitUpdate = renamed
        explicitUpdate.sportID = 1
        store.mergeWhoopWorkouts([explicitUpdate])
        XCTAssertEqual(store.whoopWorkouts().first?.sportID, 1)
    }
}

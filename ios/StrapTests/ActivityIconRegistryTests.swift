import UIKit
import XCTest
@testable import Strap

final class ActivityIconRegistryTests: XCTestCase {
    func testMappedLegacySportIDsSelectTheirEstablishedActivityKind() {
        let expected: [(Int, ActivityKind)] = [
            // Core cardio
            (0, .run),
            (1, .cycling),
            (16, .baseball),
            (17, .basketball),
            (18, .rowing),
            (19, .fencing),
            (20, .fieldHockey),
            (21, .americanFootball),
            (22, .golf),
            (24, .iceHockey),
            (25, .lacrosse),
            (27, .rugby),
            (28, .sailing),
            (29, .skiing),
            (30, .soccer),
            (31, .softball),
            (32, .squash),
            (33, .swimming),
            (34, .tennis),
            (35, .trackAndField),
            (36, .volleyball),
            (37, .waterPolo),
            (38, .wrestling),
            (39, .boxing),
            (42, .dance),
            (43, .pilates),
            (44, .yoga),
            (45, .weightlifting),
            (47, .crossCountrySkiing),
            (48, .functionalFitness),
            (49, .crossTraining),
            (51, .gymnastics),
            (52, .hiking),
            (53, .horsebackRiding),
            (55, .kayaking),
            (56, .martialArts),
            (57, .mountainBiking),
            (59, .powerlifting),
            (60, .rockClimbing),
            (61, .paddleboarding),
            (62, .crossTraining),
            (63, .walk),
            (64, .surfing),
            (65, .elliptical),
            (66, .stairClimber),
            (70, .meditation),
            (71, .other),
            (73, .diving),
            (74, .other),
            (75, .other),
            (76, .other),
            (77, .other),
            (82, .ultimateFrisbee),
            (83, .verticalClimber),
            (84, .jumpRope),
            (85, .australianFootball),
            (86, .skateboarding),
            (87, .coaching),
            (88, .iceBath),
            (89, .commuting),
            (90, .gaming),
            (91, .snowboarding),
            (92, .motocross),
            (93, .caddying),
            (94, .obstacleCourseRacing),
            (95, .motorRacing),
            (96, .hiit),
            (97, .spin),
            (98, .jiuJitsu),
            (99, .manualLabor),
            (100, .cricket),
            (101, .pickleball),
            (102, .iceSkating),
            (103, .boxFitness),
            (104, .other),
            (105, .other),
            (106, .paddleTennis),
            (107, .barre),
            (108, .stagePerformance),
            (109, .highStressWork),
            (110, .parkour),
            (111, .gaelicFootball),
            (112, .hurlingCamogie),
            (113, .circusArts),
            (121, .massageTherapy),
            (123, .strengthTraining),
            (125, .watchingSports),
            (126, .assaultBike),
            (127, .kickboxing),
            (128, .stretching),
            (230, .tableTennis),
            (231, .badminton),
            (232, .netball),
            (233, .sauna),
            (234, .discGolf),
            (235, .yardWork),
            (236, .airCompression),
            (237, .percussiveMassage),
            (238, .other),
            (239, .iceSkating),
            (240, .handball),
            (248, .f45Training),
            (249, .padel),
            (250, .berrysBootcamp),
            (251, .dedicatedParenting),
            (252, .strollerWalking),
            (253, .strollerJogging),
            (254, .toddlerwearing),
            (255, .babywearing),
            (258, .barre3),
            (259, .hotYoga),
            (261, .stairClimber),
            (262, .polo),
            (263, .musicalPerformance),
            (264, .kiteBoarding),
            (266, .dogWalking),
            (267, .waterSkiing),
            (268, .wakeboarding),
            (269, .cooking),
            (270, .cleaning),
            (272, .publicSpeaking),
        ]
        for (id, kind) in expected {
            let selected = ActivityIconRegistry.importedKind(sportID: id, sportName: "")
            XCTAssertEqual(selected, kind, "Sport ID \(id)")
            XCTAssertNotNil(UIImage(systemName: selected.icon), "Invalid SF Symbol for \(kind): \(selected.icon)")
        }
    }

    func testAllActivityKindsHaveValidIcons() {
        for kind in ActivityKind.allCases {
            XCTAssertNotNil(UIImage(systemName: kind.icon), "Invalid SF Symbol for \(kind): \(kind.icon)")
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

    func testNameBasedFallbackForUnknownLegacyIDs() {
        let nameMappings: [(String, ActivityKind)] = [
            ("sailing", .sailing),
            ("track and field", .trackAndField),
            ("water polo", .waterPolo),
            ("cross country skiing", .crossCountrySkiing),
            ("duathlon", .crossTraining),
            ("mountain biking", .mountainBiking),
            ("powerlifting", .powerlifting),
            ("triathlon", .crossTraining),
            ("diving", .diving),
            ("operations tactical", .other),
            ("ultimate", .ultimateFrisbee),
            ("climber", .verticalClimber),
            ("australian football", .australianFootball),
            ("skateboarding", .skateboarding),
            ("coaching", .coaching),
            ("ice bath", .iceBath),
            ("commuting", .commuting),
            ("gaming", .gaming),
            ("snowboarding", .snowboarding),
            ("motocross", .motocross),
            ("caddying", .caddying),
            ("obstacle course racing", .obstacleCourseRacing),
            ("motor racing", .motorRacing),
            ("jiu jitsu", .jiuJitsu),
            ("manual labor", .manualLabor),
            ("box fitness", .boxFitness),
            ("spikeball", .other),
            ("wheelchair pushing", .other),
            ("paddle tennis", .paddleTennis),
            ("barre", .barre),
            ("stage performance", .stagePerformance),
            ("high stress work", .highStressWork),
            ("parkour", .parkour),
            ("gaelic football", .gaelicFootball),
            ("hurling camogie", .hurlingCamogie),
            ("circus arts", .circusArts),
            ("massage therapy", .massageTherapy),
            ("strength trainer", .strengthTraining),
            ("watching sports", .watchingSports),
            ("assault bike", .assaultBike),
            ("kickboxing", .kickboxing),
            ("stretching", .stretching),
            ("table tennis", .tableTennis),
            ("badminton", .badminton),
            ("netball", .netball),
            ("sauna", .sauna),
            ("disc golf", .discGolf),
            ("yard work", .yardWork),
            ("air compression", .airCompression),
            ("percussive massage", .percussiveMassage),
            ("paintball", .other),
            ("ice skating", .iceSkating),
            ("handball", .handball),
            ("f45 training", .f45Training),
            ("padel", .padel),
            ("barry's", .berrysBootcamp),
            ("dedicated parenting", .dedicatedParenting),
            ("stroller walking", .strollerWalking),
            ("stroller jogging", .strollerJogging),
            ("toddlerwearing", .toddlerwearing),
            ("babywearing", .babywearing),
            ("barre3", .barre3),
            ("hot yoga", .hotYoga),
            ("stadium steps", .stairClimber),
            ("polo", .polo),
            ("musical performance", .musicalPerformance),
            ("kite boarding", .kiteBoarding),
            ("dog walking", .dogWalking),
            ("water skiing", .waterSkiing),
            ("wakeboarding", .wakeboarding),
            ("cooking", .cooking),
            ("cleaning", .cleaning),
            ("public speaking", .publicSpeaking),
        ]
        for (name, expectedKind) in nameMappings {
            let kind = ActivityIconRegistry.importedKind(sportID: nil, sportName: name)
            XCTAssertEqual(kind, expectedKind, "Name fallback failed for: \(name)")
        }
    }

    func testDuplicateLegacyIDsMapToSameKind() {
        // Australian Football (85) and Rugby (27) share the same WHOOP asset
        XCTAssertEqual(ActivityIconRegistry.importedKind(sportID: 85, sportName: ""), .australianFootball)
        XCTAssertEqual(ActivityIconRegistry.importedKind(sportID: 27, sportName: ""), .rugby)
        
        // Other (71) and Activity (-1) share the same WHOOP asset
        // -1 is not in the registry but would fall back to .other
        
        // Weightlifting (45) and Strength Trainer (123) share the same WHOOP asset
        XCTAssertEqual(ActivityIconRegistry.importedKind(sportID: 45, sportName: ""), .weightlifting)
        XCTAssertEqual(ActivityIconRegistry.importedKind(sportID: 123, sportName: ""), .strengthTraining)
    }
}
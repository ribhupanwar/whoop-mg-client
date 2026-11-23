import Foundation

// MARK: - Manual activities

enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    // Core activities
    case lift
    case run
    case walk
    case cardio
    case other
    
    // Cycling & wheeled
    case cycling, mountainBiking, spin, cyclingIndoor
    
    // Water sports
    case swimming, surfing, paddleboarding, kayaking, canoeing, rowing, sailing, diving, waterPolo, waterSkiing, wakeboarding
    
    // Mind-body & recovery
    case yoga, hotYoga, pilates, barre, barre3, meditation, stretching, mobility, massageTherapy, percussiveMassage, airCompression, sauna, iceBath
    
    // Dance & gymnastics
    case dance, gymnastics, aerobics, circusArts, cheerleading
    
    // Outdoor & adventure
    case hiking, climbing, rockClimbing, verticalClimber, mountaineering, trailRun, parkour, obstacleCourseRacing
    
    // Winter sports
    case skiing, crossCountrySkiing, snowboarding, iceSkating, iceHockey
    
    // Team sports (ball)
    case basketball, football, americanFootball, soccer, rugby, volleyball, handball, baseball, softball, cricket, lacrosse, fieldHockey, gaelicFootball, hurlingCamogie, australianFootball, ultimateFrisbee, netball, polo
    
    // Racquet/paddle sports
    case tennis, tableTennis, badminton, pickleball, squash, racquetball, padel, paddleTennis
    
    // Combat sports
    case boxing, martialArts, wrestling, fencing, jiuJitsu, kickboxing
    
    // Precision sports
    case golf, discGolf, archery, shooting, pool, bowling
    
    // Fitness equipment & gym
    case elliptical, stairClimber, treadmill, assaultBike, functionalFitness, crossTraining, hiit, strengthTraining, weightlifting, powerlifting, boxFitness, f45Training, berrysBootcamp
    
    // Running variants
    case outdoorRun, intervalRun, indoorRun, trackAndField
    
    // Walking variants
    case indoorWalk, commuting, dogWalking, strollerWalking, strollerJogging
    
    // Strength & conditioning
    case jumpRope, calisthenics
    
    // Equestrian
    case horsebackRiding
    
    // Lifestyle & other
    case gardening, yardWork, caddying, manualLabor, coaching, highStressWork, gaming, stagePerformance, musicalPerformance, publicSpeaking, cooking, cleaning, dedicatedParenting, babywearing, toddlerwearing, watchingSports, spectating, motocross, motorRacing, kiteBoarding, skateboarding
    
    // Recovery & wellness
    case sleep, nap

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lift: return "Lift"
        case .run: return "Run"
        case .walk: return "Walk"
        case .cardio: return "Cardio"
        case .other: return "Other"
        case .cycling: return "Cycling"
        case .mountainBiking: return "Mountain Biking"
        case .spin: return "Spin"
        case .cyclingIndoor: return "Indoor Cycling"
        case .swimming: return "Swimming"
        case .surfing: return "Surfing"
        case .paddleboarding: return "Paddleboarding"
        case .kayaking: return "Kayaking"
        case .canoeing: return "Canoeing"
        case .rowing: return "Rowing"
        case .sailing: return "Sailing"
        case .diving: return "Diving"
        case .waterPolo: return "Water Polo"
        case .waterSkiing: return "Water Skiing"
        case .wakeboarding: return "Wakeboarding"
        case .yoga: return "Yoga"
        case .hotYoga: return "Hot Yoga"
        case .pilates: return "Pilates"
        case .barre: return "Barre"
        case .barre3: return "Barre3"
        case .meditation: return "Meditation"
        case .stretching: return "Stretching"
        case .mobility: return "Mobility"
        case .massageTherapy: return "Massage Therapy"
        case .percussiveMassage: return "Percussive Massage"
        case .airCompression: return "Air Compression"
        case .sauna: return "Sauna"
        case .iceBath: return "Ice Bath"
        case .dance: return "Dance"
        case .gymnastics: return "Gymnastics"
        case .aerobics: return "Aerobics"
        case .circusArts: return "Circus Arts"
        case .cheerleading: return "Cheerleading"
        case .hiking: return "Hiking"
        case .climbing: return "Climbing"
        case .rockClimbing: return "Rock Climbing"
        case .verticalClimber: return "Vertical Climber"
        case .mountaineering: return "Mountaineering"
        case .trailRun: return "Trail Running"
        case .parkour: return "Parkour"
        case .obstacleCourseRacing: return "Obstacle Course Racing"
        case .skiing: return "Skiing"
        case .crossCountrySkiing: return "Cross Country Skiing"
        case .snowboarding: return "Snowboarding"
        case .iceSkating: return "Ice Skating"
        case .iceHockey: return "Ice Hockey"
        case .basketball: return "Basketball"
        case .football: return "Football"
        case .americanFootball: return "American Football"
        case .soccer: return "Soccer"
        case .rugby: return "Rugby"
        case .volleyball: return "Volleyball"
        case .handball: return "Handball"
        case .baseball: return "Baseball"
        case .softball: return "Softball"
        case .cricket: return "Cricket"
        case .lacrosse: return "Lacrosse"
        case .fieldHockey: return "Field Hockey"
        case .gaelicFootball: return "Gaelic Football"
        case .hurlingCamogie: return "Hurling/Camogie"
        case .australianFootball: return "Australian Rules Football"
        case .ultimateFrisbee: return "Ultimate Frisbee"
        case .netball: return "Netball"
        case .polo: return "Polo"
        case .tennis: return "Tennis"
        case .tableTennis: return "Table Tennis"
        case .badminton: return "Badminton"
        case .pickleball: return "Pickleball"
        case .squash: return "Squash"
        case .racquetball: return "Racquetball"
        case .padel: return "Padel"
        case .paddleTennis: return "Paddle Tennis"
        case .boxing: return "Boxing"
        case .martialArts: return "Martial Arts"
        case .wrestling: return "Wrestling"
        case .fencing: return "Fencing"
        case .jiuJitsu: return "Jiu Jitsu"
        case .kickboxing: return "Kickboxing"
        case .golf: return "Golf"
        case .discGolf: return "Disc Golf"
        case .archery: return "Archery"
        case .shooting: return "Shooting"
        case .pool: return "Pool"
        case .bowling: return "Bowling"
        case .elliptical: return "Elliptical"
        case .stairClimber: return "Stair Climber"
        case .treadmill: return "Treadmill"
        case .assaultBike: return "Assault Bike"
        case .functionalFitness: return "Functional Fitness"
        case .crossTraining: return "Cross Training"
        case .hiit: return "HIIT"
        case .strengthTraining: return "Strength Training"
        case .weightlifting: return "Weightlifting"
        case .powerlifting: return "Powerlifting"
        case .boxFitness: return "Box Fitness"
        case .f45Training: return "F45 Training"
        case .berrysBootcamp: return "Barry's"
        case .outdoorRun: return "Outdoor Running"
        case .intervalRun: return "Interval Running"
        case .indoorRun: return "Indoor Running"
        case .trackAndField: return "Track & Field"
        case .indoorWalk: return "Indoor Walking"
        case .commuting: return "Commuting"
        case .dogWalking: return "Dog Walking"
        case .strollerWalking: return "Stroller Walking"
        case .strollerJogging: return "Stroller Jogging"
        case .jumpRope: return "Jump Rope"
        case .calisthenics: return "Calisthenics"
        case .horsebackRiding: return "Horseback Riding"
        case .gardening: return "Gardening"
        case .yardWork: return "Yard Work"
        case .caddying: return "Caddying"
        case .manualLabor: return "Manual Labor"
        case .coaching: return "Coaching"
        case .highStressWork: return "High Stress Work"
        case .gaming: return "Gaming"
        case .stagePerformance: return "Stage Performance"
        case .musicalPerformance: return "Musical Performance"
        case .publicSpeaking: return "Public Speaking"
        case .cooking: return "Cooking"
        case .cleaning: return "Cleaning"
        case .dedicatedParenting: return "Dedicated Parenting"
        case .babywearing: return "Babywearing"
        case .toddlerwearing: return "Toddlerwearing"
        case .watchingSports: return "Watching Sports"
        case .spectating: return "Spectating"
        case .motocross: return "Motocross"
        case .motorRacing: return "Motor Racing"
        case .kiteBoarding: return "Kite Boarding"
        case .skateboarding: return "Skateboarding"
        case .sleep: return "Sleep"
        case .nap: return "Nap"
        }
    }

var icon: String {
        switch self {
        case .lift: return "dumbbell.fill"
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cardio: return "heart.fill"
        case .other: return "figure.mixed.cardio"
        case .cycling, .mountainBiking, .cyclingIndoor: return "bicycle"
        case .spin: return "figure.indoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .waterPolo: return "figure.water.polo"
        case .surfing: return "figure.surfing"
        case .paddleboarding, .kayaking, .canoeing, .waterSkiing, .wakeboarding, .kiteBoarding: return "figure.pool.swim"
        case .rowing: return "figure.rower"
        case .sailing: return "sailboat.fill"
        case .diving: return "figure.pool.swim"
        case .yoga: return "figure.yoga"
        case .hotYoga: return "figure.yoga"
        case .pilates: return "figure.pilates"
        case .barre, .barre3: return "figure.cooldown"
        case .meditation: return "figure.mind.and.body"
        case .stretching, .mobility: return "figure.cooldown"
        case .massageTherapy, .percussiveMassage: return "figure.mind.and.body"
        case .airCompression: return "lungs.fill"
        case .sauna: return "flame.fill"
        case .iceBath: return "snowflake"
        case .dance: return "figure.dance"
        case .gymnastics: return "figure.gymnastics"
        case .aerobics: return "figure.highintensity.intervaltraining"
        case .circusArts: return "figure.dance"
        case .cheerleading: return "figure.dance"
        case .hiking: return "figure.hiking"
        case .climbing, .rockClimbing, .verticalClimber: return "figure.climbing"
        case .mountaineering: return "figure.hiking"
        case .trailRun: return "figure.run"
        case .parkour: return "figure.highintensity.intervaltraining"
        case .obstacleCourseRacing: return "figure.highintensity.intervaltraining"
        case .skiing: return "figure.skiing.downhill"
        case .crossCountrySkiing: return "figure.skiing.crosscountry"
        case .snowboarding: return "figure.snowboarding"
        case .iceSkating: return "figure.skating"
        case .iceHockey, .fieldHockey, .hurlingCamogie: return "figure.hockey"
        case .basketball: return "basketball.fill"
        case .football, .americanFootball: return "football.fill"
        case .soccer: return "soccerball"
        case .rugby: return "football.fill"
        case .volleyball: return "figure.volleyball"
        case .handball: return "figure.handball"
        case .baseball: return "baseball.fill"
        case .softball: return "baseball.fill"
        case .cricket: return "figure.cricket"
        case .lacrosse: return "figure.lacrosse"
        case .gaelicFootball: return "football.fill"
        case .australianFootball: return "football.fill"
        case .ultimateFrisbee, .discGolf: return "figure.disc.sports"
        case .netball: return "basketball.fill"
        case .polo: return "figure.equestrian.sports"
        case .tennis: return "tennis.racket"
        case .tableTennis: return "figure.table.tennis"
        case .badminton: return "figure.badminton"
        case .pickleball, .squash, .racquetball, .padel, .paddleTennis: return "tennis.racket"
        case .boxing, .kickboxing: return "figure.boxing"
        case .martialArts, .jiuJitsu: return "figure.martial.arts"
        case .wrestling: return "figure.wrestling"
        case .fencing: return "figure.fencing"
        case .golf: return "figure.golf"
        case .archery: return "figure.archery"
        case .shooting: return "scope"
        case .pool: return "circle.grid.cross.fill"
        case .bowling: return "figure.bowling"
        case .elliptical: return "figure.elliptical"
        case .stairClimber: return "figure.stair.stepper"
        case .treadmill: return "figure.walk"
        case .assaultBike: return "bicycle"
        case .functionalFitness: return "figure.strengthtraining.functional"
        case .crossTraining: return "figure.highintensity.intervaltraining"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .strengthTraining: return "figure.strengthtraining.traditional"
        case .weightlifting: return "dumbbell.fill"
        case .powerlifting: return "dumbbell"
        case .boxFitness: return "figure.boxing"
        case .f45Training: return "figure.highintensity.intervaltraining"
        case .berrysBootcamp: return "figure.highintensity.intervaltraining"
        case .outdoorRun: return "figure.run"
        case .intervalRun: return "figure.run"
        case .indoorRun: return "figure.run"
        case .trackAndField: return "figure.run"
        case .indoorWalk: return "figure.walk"
        case .commuting: return "figure.walk"
        case .dogWalking: return "figure.walk"
        case .strollerWalking, .strollerJogging: return "figure.walk"
        case .jumpRope: return "figure.jumprope"
        case .calisthenics: return "figure.strengthtraining.traditional"
        case .horsebackRiding: return "figure.equestrian.sports"
        case .gardening, .yardWork: return "leaf.fill"
        case .caddying: return "figure.golf"
        case .manualLabor: return "hammer.fill"
        case .coaching: return "megaphone.fill"
        case .highStressWork: return "brain.head.profile"
        case .gaming: return "gamecontroller.fill"
        case .stagePerformance, .musicalPerformance: return "music.mic"
        case .publicSpeaking: return "person.wave.2.fill"
        case .cooking: return "frying.pan.fill"
        case .cleaning: return "sparkles"
        case .dedicatedParenting, .babywearing, .toddlerwearing: return "figure.2.arms.open"
        case .watchingSports, .spectating: return "tv.fill"
        case .motocross: return "motorcycle.fill"
        case .motorRacing: return "car.fill"
        case .skateboarding: return "figure.skateboarding"
        case .sleep: return "moon.fill"
        case .nap: return "moon.zzz.fill"
        }
    }

    /// Lifting is entered as sets; everything else by minutes.
    var usesSets: Bool { 
        self == .lift || self == .strengthTraining || self == .weightlifting || self == .powerlifting || self == .calisthenics
    }
}

/// Presentation mapping based on WHOOP's public legacy sport table. The
/// names and IDs are input metadata. Existing identifiers and spelling in saved
/// records is preserved by the importer.
enum ActivityIconRegistry {
    static let sleep = "moon.fill"
    static let nap = "moon.zzz.fill"

    // https://developer.whoop.com/docs/developing/user-data/workout/#whoop-sports
    // Complete mapping of all 122 legacy sport IDs from WHOOP v5.80.2
    private static let importedSports: [(id: Int, name: String, kind: ActivityKind)] = [
        // Core cardio
        (0, "Running", .run),
        (1, "Cycling", .cycling),
        (16, "Baseball", .baseball),
        (17, "Basketball", .basketball),
        (18, "Rowing", .rowing),
        (19, "Fencing", .fencing),
        (20, "Field Hockey", .fieldHockey),
        (21, "Football", .americanFootball),
        (22, "Golf", .golf),
        (24, "Ice Hockey", .iceHockey),
        (25, "Lacrosse", .lacrosse),
        (27, "Rugby", .rugby),
        (28, "Sailing", .sailing),
        (29, "Skiing", .skiing),
        (30, "Soccer", .soccer),
        (31, "Softball", .softball),
        (32, "Squash", .squash),
        (33, "Swimming", .swimming),
        (34, "Tennis", .tennis),
        (35, "Track & Field", .trackAndField),
        (36, "Volleyball", .volleyball),
        (37, "Water Polo", .waterPolo),
        (38, "Wrestling", .wrestling),
        (39, "Boxing", .boxing),
        (42, "Dance", .dance),
        (43, "Pilates", .pilates),
        (44, "Yoga", .yoga),
        (45, "Weightlifting", .weightlifting),
        (47, "Cross Country Skiing", .crossCountrySkiing),
        (48, "Functional Fitness", .functionalFitness),
        (49, "Duathlon", .crossTraining),
        (51, "Gymnastics", .gymnastics),
        (52, "Hiking/Rucking", .hiking),
        (53, "Horseback Riding", .horsebackRiding),
        (55, "Kayaking", .kayaking),
        (56, "Martial Arts", .martialArts),
        (57, "Mountain Biking", .mountainBiking),
        (59, "Powerlifting", .powerlifting),
        (60, "Rock Climbing", .rockClimbing),
        (61, "Paddleboarding", .paddleboarding),
        (62, "Triathlon", .crossTraining),
        (63, "Walking", .walk),
        (64, "Surfing", .surfing),
        (65, "Elliptical", .elliptical),
        (66, "Stairmaster", .stairClimber),
        (70, "Meditation", .meditation),
        (71, "Other", .other),
        (73, "Diving", .diving),
        (74, "Operations - Tactical", .other),
        (75, "Operations - Medical", .other),
        (76, "Operations - Flying", .other),
        (77, "Operations - Water", .other),
        (82, "Ultimate", .ultimateFrisbee),
        (83, "Climber", .verticalClimber),
        (84, "Jumping Rope", .jumpRope),
        (85, "Australian Football", .australianFootball),
        (86, "Skateboarding", .skateboarding),
        (87, "Coaching", .coaching),
        (88, "Ice Bath", .iceBath),
        (89, "Commuting", .commuting),
        (90, "Gaming", .gaming),
        (91, "Snowboarding", .snowboarding),
        (92, "Motocross", .motocross),
        (93, "Caddying", .caddying),
        (94, "Obstacle Course Racing", .obstacleCourseRacing),
        (95, "Motor Racing", .motorRacing),
        (96, "HIIT", .hiit),
        (97, "Spin", .spin),
        (98, "Jiu Jitsu", .jiuJitsu),
        (99, "Manual Labor", .manualLabor),
        (100, "Cricket", .cricket),
        (101, "Pickleball", .pickleball),
        (102, "Inline Skating", .iceSkating),
        (103, "Box Fitness", .boxFitness),
        (104, "Spikeball", .other),
        (105, "Wheelchair Pushing", .other),
        (106, "Paddle Tennis", .paddleTennis),
        (107, "Barre", .barre),
        (108, "Stage Performance", .stagePerformance),
        (109, "High Stress Work", .highStressWork),
        (110, "Parkour", .parkour),
        (111, "Gaelic Football", .gaelicFootball),
        (112, "Hurling/Camogie", .hurlingCamogie),
        (113, "Circus Arts", .circusArts),
        (121, "Massage Therapy", .massageTherapy),
        (123, "Strength Trainer", .strengthTraining),
        (125, "Watching Sports", .watchingSports),
        (126, "Assault Bike", .assaultBike),
        (127, "Kickboxing", .kickboxing),
        (128, "Stretching", .stretching),
        (230, "Table Tennis", .tableTennis),
        (231, "Badminton", .badminton),
        (232, "Netball", .netball),
        (233, "Sauna", .sauna),
        (234, "Disc Golf", .discGolf),
        (235, "Yard Work", .yardWork),
        (236, "Air Compression", .airCompression),
        (237, "Percussive Massage", .percussiveMassage),
        (238, "Paintball", .other),
        (239, "Ice Skating", .iceSkating),
        (240, "Handball", .handball),
        (248, "F45 Training", .f45Training),
        (249, "Padel", .padel),
        (250, "Barry's", .berrysBootcamp),
        (251, "Dedicated Parenting", .dedicatedParenting),
        (252, "Stroller Walking", .strollerWalking),
        (253, "Stroller Jogging", .strollerJogging),
        (254, "Toddlerwearing", .toddlerwearing),
        (255, "Babywearing", .babywearing),
        (258, "Barre3", .barre3),
        (259, "Hot Yoga", .hotYoga),
        (261, "Stadium Steps", .stairClimber),
        (262, "Polo", .polo),
        (263, "Musical Performance", .musicalPerformance),
        (264, "Kite Boarding", .kiteBoarding),
        (266, "Dog Walking", .dogWalking),
        (267, "Water Skiing", .waterSkiing),
        (268, "Wakeboarding", .wakeboarding),
        (269, "Cooking", .cooking),
        (270, "Cleaning", .cleaning),
        (272, "Public Speaking", .publicSpeaking),
    ]

    static func importedKind(sportID: Int?, sportName: String) -> ActivityKind {
        let name = normalized(sportName)
        let nameKind = (name == "track and field" ? ActivityKind.trackAndField : nil)
            ?? (name == "hurling camogie" ? ActivityKind.hurlingCamogie : nil)
            ?? importedSports.first { normalized($0.name) == name }?.kind
            ?? ActivityKind.allCases.first { normalized($0.label) == name }
        if let sportID {
            guard let legacyKind = importedSports.first(where: { $0.id == sportID })?.kind else {
                return .other
            }
            return nameKind ?? legacyKind
        }
        return nameKind ?? .other
    }

    static func detectedIcon(_ kind: String) -> String {
        switch kind {
        case "run": return ActivityKind.run.icon
        case "walk": return ActivityKind.walk.icon
        case "workout": return ActivityKind.lift.icon
        case "cardio": return ActivityKind.cardio.icon
        default: return ActivityKind.other.icon
        }
    }

    private static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

/// One set of a lift: reps at a load. The band sends no load, so this is
/// always self-reported.
struct WorkSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var reps: Int
    var loadKG: Double

    var volumeKG: Double { Double(reps) * loadKG }
}

/// A self-entered session. Never mixed into strain or recovery — those stay
/// sensor-derived. Manual entries are the log, not a measurement.
struct ManualActivity: Codable, Equatable, Identifiable {
    var id = UUID()
    var dateKey: String
    var kind: ActivityKind
    var name: String
    var minutes: Int
    var sets: [WorkSet]
    var notes: String
    let mergedFrom: [ManualActivity]?

    init(
        id: UUID = UUID(),
        dateKey: String,
        kind: ActivityKind,
        name: String,
        minutes: Int,
        sets: [WorkSet] = [],
        notes: String = "",
        mergedFrom: [ManualActivity]? = nil
    ) {
        self.id = id
        self.dateKey = dateKey
        self.kind = kind
        self.name = name
        self.minutes = minutes
        self.sets = sets
        self.notes = notes
        self.mergedFrom = mergedFrom
    }

    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    var volumeKG: Double { sets.reduce(0.0) { $0 + $1.volumeKG } }

    var summary: String {
        if kind.usesSets, !sets.isEmpty {
            return "\(sets.count) sets · \(totalReps) reps · \(Int(volumeKG.rounded())) kg"
        }
        return "\(minutes) min"
    }
}

// MARK: - Live sessions

/// One measured live HR session from the standard heart-rate profile.
struct LiveActivityRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var dateKey: String
    let startedUnix: Int
    let endedUnix: Int
    let meanHR: Double?
    let maxHR: Int?
    let beats: Int
    let hrv: HrvResult
    /// Seconds spent in each Karvonen zone (Z1…Z5). Empty when zones were
    /// unavailable, so the UI can say so instead of showing zeros.
    let zoneSeconds: [Int]

    var seconds: Int { max(0, endedUnix - startedUnix) }
    var minutes: Double { Double(seconds) / 60.0 }
}

enum LiveZones {
    /// Each sample stands for the gap until the next one (1–5 s). Heart rates
    /// below Z1 or above max HR count toward no zone.
    static func seconds(samples: [LiveSample], zones: [HRZone]?) -> [Int] {
        guard let zones, !zones.isEmpty else { return [] }
        var buckets = [Int](repeating: 0, count: zones.count)
        let valid = samples.filter { (25...230).contains($0.heartRate) }
        let ordered = Dictionary(valid.map { ($0.unix, $0) }, uniquingKeysWith: { _, last in last })
            .values.sorted { $0.unix < $1.unix }
        for (index, sample) in ordered.enumerated() {
            let next = index + 1 < ordered.count ? ordered[index + 1].unix : sample.unix + 1
            let gap = next - sample.unix
            let span = gap > 30 ? 1 : max(1, min(5, gap))
            let hr = Double(sample.heartRate)
            if let index = Karvonen.zoneIndex(heartRate: hr, zones: zones),
               let zoneIndex = zones.firstIndex(where: { $0.index == index }) {
                buckets[zoneIndex] += span
            }
        }
        return buckets
    }
}

// MARK: - Formatting

enum ActivityFormat {
    /// Minutes as h:mm, the same shape the dashboard uses for weekly zone time.
    static func clock(minutes: Double) -> String {
        let seconds = Int((minutes * 60).rounded())
        return String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    /// Milliseconds as a whole number with an optional unit.
    static func whole(_ value: Double?, unit: String = "") -> String? {
        guard let value else { return nil }
        return String(format: "%.0f", value) + unit
    }
}


struct WhoopWorkout: Codable, Equatable, Identifiable {
    let id: String
    let sportName: String
    let startUnix: Int
    let endUnix: Int
    let strain: Double?
    let averageHeartRate: Int?
    var sportID: Int? = nil

    var activityIcon: String {
        ActivityIconRegistry.importedKind(sportID: sportID, sportName: sportName).icon
    }
}

enum WhoopWorkoutImport {
    private struct Page: Decodable {
        let records: [Record]
        let next_token: String?
    }
    private struct Record: Decodable {
        let id: String
        let sport_name: String
        let sport_id: Int?
        let start: Date
        let end: Date
        let score: Score?
    }
    private struct Score: Decodable {
        let strain: Double?
        let average_heart_rate: Int?
    }

    /// One authorized WHOOP API v2 workout page; paginate using next_token.
    static func decodePage(_ data: Data) throws -> (workouts: [WhoopWorkout], nextToken: String?) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: value) ?? plain.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 workout timestamp")
            }
            return date
        }
        let page = try decoder.decode(Page.self, from: data)
        let workouts = page.records.compactMap { item -> WhoopWorkout? in
            guard item.end > item.start, !item.id.isEmpty else { return nil }
            return WhoopWorkout(
                id: item.id, sportName: item.sport_name,
                startUnix: Int(item.start.timeIntervalSince1970),
                endUnix: Int(item.end.timeIntervalSince1970),
                strain: item.score?.strain,
                averageHeartRate: item.score?.average_heart_rate, sportID: item.sport_id
            )
        }
        return (workouts, page.next_token)
    }
}

// MARK: - Persistence

/// UserDefaults-backed activity log. Manual entries, measured live sessions
/// and band-detected sessions are stored separately so none can be mistaken
/// for another.
private struct DeletedDetectedActivity: Codable, Equatable {
    let startUnix: Int
    let endUnix: Int
    let deletedAtUnix: Int
}

final class ActivityStore {
    private let detectedLock = NSRecursiveLock()
    private var detectedRevision: UInt64 = 0
    private var cachedDetected: [ActivitySession]?
    private var cachedDeletions: [DeletedDetectedActivity]?
    private let defaults: UserDefaults
    private let manualRevisionDirectory: URL
    private(set) var lastManualWriteError: String?
    static var revisionArchiveDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures/activity-revisions", isDirectory: true)
    }
    private let manualKey = "strap.activities.v1"
    private let liveKey = "strap.live.sessions.v1"
    private let detectedKey = "strap.detected.activities.v1"
    private let deletedDetectedKey = "strap.detected.activities.deleted.v1"
    private let whoopKey = "strap.whoop.official.workouts.v1"

    init(defaults: UserDefaults = .standard, revisionDirectory: URL? = nil) {
        self.defaults = defaults
        self.manualRevisionDirectory = revisionDirectory ?? (defaults === UserDefaults.standard
            ? Self.revisionArchiveDirectory
            : FileManager.default.temporaryDirectory.appendingPathComponent("STRAP-activity-revisions-" + UUID().uuidString))
    }

    func manualActivities() -> [ManualActivity] {
        guard let data = defaults.data(forKey: manualKey),
              let saved = try? JSONDecoder().decode([ManualActivity].self, from: data) else {
            return []
        }
        return saved.sorted { $0.dateKey < $1.dateKey }
    }

    func liveActivities() -> [LiveActivityRecord] {
        guard let data = defaults.data(forKey: liveKey),
              let saved = try? JSONDecoder().decode([LiveActivityRecord].self, from: data) else {
            return []
        }
        return saved.sorted { $0.startedUnix < $1.startedUnix }
    }

    private func strictManualActivities() throws -> [ManualActivity] {
        guard let original = defaults.object(forKey: manualKey) else { return [] }
        guard let bytes = original as? Data else {
            throw PersistenceDiagnostics.Failure(message: "Original activity history could not be read; it was preserved.")
        }
        return try JSONDecoder().decode([ManualActivity].self, from: bytes)
    }

    private func archiveManualRevision(_ original: Data, directory: URL? = nil) throws {
        let destination = directory ?? manualRevisionDirectory
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let archive = destination.appendingPathComponent(PersistenceDiagnostics.digest(original) + ".json")
        if FileManager.default.fileExists(atPath: archive.path) {
            guard try Data(contentsOf: archive) == original else {
                throw PersistenceDiagnostics.Failure(message: "Activity archive conflict; original history preserved.")
            }
        } else { try original.write(to: archive, options: .atomic) }
    }

    private func persistManual(_ items: [ManualActivity]) throws {
        let bytes = try JSONEncoder().encode(items)
        if let original = defaults.data(forKey: manualKey) { try archiveManualRevision(original) }
        defaults.set(bytes, forKey: manualKey)
    }

    @discardableResult
    func save(_ activity: ManualActivity) -> Bool {
        do {
            var items = try strictManualActivities()
            if let index = items.firstIndex(where: { $0.id == activity.id }) { items[index] = activity }
            else { items.append(activity) }
            try persistManual(items)
            lastManualWriteError = nil
            return true
        } catch { lastManualWriteError = error.localizedDescription; return false }
    }

    @discardableResult
    func restoreMissingManual(_ activity: ManualActivity) throws -> Bool {
        var items = try strictManualActivities()
        guard !items.contains(where: { $0.id == activity.id }) else { return false }
        items.append(activity)
        try persistManual(items)
        return true
    }

    @discardableResult
    func mergeManual(ids: Set<UUID>, name: String) throws -> ManualActivity {
        guard ids.count >= 2, let original = defaults.data(forKey: manualKey) else {
            throw PersistenceDiagnostics.Failure(message: "Select at least two manual entries.")
        }
        let items = try JSONDecoder().decode([ManualActivity].self, from: original)
        let selected = items.filter { ids.contains($0.id) }
        guard selected.count == ids.count, let first = selected.first,
              selected.allSatisfy({ $0.dateKey == first.dateKey && $0.kind == first.kind && $0.minutes >= 0 }) else {
            throw PersistenceDiagnostics.Failure(message: "Merge only existing manual entries of the same type and date.")
        }
        var minutes = 0
        for item in selected {
            let sum = minutes.addingReportingOverflow(item.minutes)
            guard !sum.overflow else { throw PersistenceDiagnostics.Failure(message: "Combined duration is too large.") }
            minutes = sum.partialValue
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let merged = ManualActivity(dateKey: first.dateKey, kind: first.kind,
            name: title.isEmpty ? first.kind.label + " (merged)" : title, minutes: minutes,
            sets: selected.flatMap(\.sets), notes: selected.map { $0.name + ": " + $0.notes }.joined(separator: "\n"),
            mergedFrom: selected)
        try archiveManualRevision(original)
        let updated = items.filter { !ids.contains($0.id) } + [merged]
        defaults.set(try JSONEncoder().encode(updated), forKey: manualKey)
        return merged
    }

    func undoManualMerge(id: UUID) throws {
        guard let original = defaults.data(forKey: manualKey) else {
            throw PersistenceDiagnostics.Failure(message: "Manual history is unavailable.")
        }
        let items = try JSONDecoder().decode([ManualActivity].self, from: original)
        guard let merged = items.first(where: { $0.id == id }),
              let retained = merged.mergedFrom, !retained.isEmpty else {
            throw PersistenceDiagnostics.Failure(message: "No retained merge originals found.")
        }
        var updated = items.filter { $0.id != id }
        for row in retained {
            if let existing = updated.first(where: { $0.id == row.id }) {
                guard existing == row else {
                    throw PersistenceDiagnostics.Failure(message: "An original entry was changed separately; undo cancelled to preserve it.")
                }
            } else { updated.append(row) }
        }
        try archiveManualRevision(original)
        defaults.set(try JSONEncoder().encode(updated), forKey: manualKey)
    }

    @discardableResult
    func deleteManual(id: UUID) -> Bool {
        do {
            let items = try strictManualActivities()
            guard items.contains(where: { $0.id == id }) else { lastManualWriteError = nil; return true }
            try persistManual(items.filter { $0.id != id })
            lastManualWriteError = nil
            return true
        } catch { lastManualWriteError = error.localizedDescription; return false }
    }

    // Never overwrite an unreadable live-session archive with an empty decoded list.
    private func readableLiveActivities() -> [LiveActivityRecord]? {
        guard let original = defaults.object(forKey: liveKey) else { return [] }
        guard let bytes = original as? Data else { return nil }
        return try? JSONDecoder().decode([LiveActivityRecord].self, from: bytes)
    }

    func saveLive(_ record: LiveActivityRecord) {
        guard var items = readableLiveActivities() else { return }
        if let index = items.firstIndex(where: { $0.id == record.id }) {
            items[index] = record
        } else {
            items.append(record)
        }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: liveKey)
        }
    }

    func deleteLive(id: UUID) {
        guard let existing = readableLiveActivities() else { return }
        let items = existing.filter { $0.id != id }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: liveKey)
        }
    }

    func whoopWorkouts() -> [WhoopWorkout] {
        guard let data = defaults.data(forKey: whoopKey),
              let saved = try? JSONDecoder().decode([WhoopWorkout].self, from: data) else {
            return []
        }
        return saved.sorted { $0.startUnix < $1.startUnix }
    }

    func mergeWhoopWorkouts(_ incoming: [WhoopWorkout]) {
        var byID = Dictionary(uniqueKeysWithValues: whoopWorkouts().map { ($0.id, $0) })
        for var item in incoming {
            item.sportID = item.sportID ?? byID[item.id]?.sportID
            byID[item.id] = item
        }
        if let data = try? JSONEncoder().encode(Array(byID.values)) {
            defaults.set(data, forKey: whoopKey)
        }
    }

    // MARK: - Band-detected sessions

    private func loadedDeletedSessionsLocked() -> [DeletedDetectedActivity] {
        if let cached = cachedDeletions { return cached }
        guard let data = defaults.data(forKey: deletedDetectedKey),
              let saved = try? JSONDecoder().decode([DeletedDetectedActivity].self, from: data) else {
            cachedDeletions = []
            return []
        }
        cachedDeletions = saved
        return saved
    }

    private func loadedDetectedSessionsLocked(deletions: [DeletedDetectedActivity]) -> [ActivitySession] {
        let saved: [ActivitySession]
        if let cached = cachedDetected {
            saved = cached
        } else if let data = defaults.data(forKey: detectedKey),
                  let loaded = try? JSONDecoder().decode([ActivitySession].self, from: data) {
            cachedDetected = loaded
            saved = loaded
        } else {
            cachedDetected = []
            saved = []
        }
        return saved.filter { session in !deletions.contains { Self.matches(session, deletion: $0) } }
            .sorted { $0.startUnix < $1.startUnix }
    }

    func detectedActivities() -> [ActivitySession] {
        detectedLock.lock()
        defer { detectedLock.unlock() }
        let deletions = loadedDeletedSessionsLocked()
        return loadedDetectedSessionsLocked(deletions: deletions)
    }

    /// Hides a deleted band session across replays whose boundaries shift slightly.
    func isDetectedDeleted(_ session: ActivitySession) -> Bool {
        detectedLock.lock()
        defer { detectedLock.unlock() }
        return loadedDeletedSessionsLocked().contains { Self.matches(session, deletion: $0) }
    }

    func deletedDetectedStartTimes() -> [Int] {
        detectedLock.lock()
        defer { detectedLock.unlock() }
        return Array(Set(loadedDeletedSessionsLocked().map(\.startUnix))).sorted()
    }

    private struct DetectedSnapshot {
        let revision: UInt64
        let activities: [ActivitySession]
        let deletions: [DeletedDetectedActivity]
    }

    private func stageDetectedLocked(_ activities: [ActivitySession], deletions: [DeletedDetectedActivity]) -> DetectedSnapshot {
        cachedDetected = activities
        cachedDeletions = deletions
        detectedRevision &+= 1
        return DetectedSnapshot(revision: detectedRevision, activities: activities, deletions: deletions)
    }

    private func isLatestDetectedSnapshot(_ snapshot: DetectedSnapshot) -> Bool {
        detectedLock.lock()
        defer { detectedLock.unlock() }
        return detectedRevision == snapshot.revision
    }

    private func persistDetected(_ snapshot: DetectedSnapshot) {
        guard let activities = try? JSONEncoder().encode(snapshot.activities),
              let deletions = try? JSONEncoder().encode(snapshot.deletions) else { return }
        let write = {
            // UserDefaults can synchronously notify observers. Run delivery on
            // main without holding a lock that a reader or another writer needs.
            guard self.isLatestDetectedSnapshot(snapshot) else { return }
            if !snapshot.deletions.isEmpty {
                self.defaults.set(deletions, forKey: self.deletedDetectedKey)
            }
            // A reentrant observer may have staged and saved a newer snapshot.
            guard self.isLatestDetectedSnapshot(snapshot) else { return }
            self.defaults.set(activities, forKey: self.detectedKey)
        }
        if Thread.isMainThread {
            write()
        } else {
            DispatchQueue.main.async(execute: write)
        }
    }

    func deleteDetected(_ session: ActivitySession, now: Date = Date()) {
        let snapshot: DetectedSnapshot? = {
            detectedLock.lock()
            defer { detectedLock.unlock() }
            // Preserve unreadable saved activity or deletion records.
            if let original = defaults.data(forKey: detectedKey),
               (try? JSONDecoder().decode([ActivitySession].self, from: original)) == nil { return nil }
            if let original = defaults.data(forKey: deletedDetectedKey),
               (try? JSONDecoder().decode([DeletedDetectedActivity].self, from: original)) == nil { return nil }

            var deletions = loadedDeletedSessionsLocked()
            if !deletions.contains(where: { Self.matches(session, deletion: $0) }) {
                deletions.append(DeletedDetectedActivity(
                    startUnix: session.startUnix, endUnix: session.endUnix,
                    deletedAtUnix: Int(now.timeIntervalSince1970)
                ))
            }
            let remaining = loadedDetectedSessionsLocked(deletions: deletions)
            return stageDetectedLocked(remaining, deletions: deletions)
        }()

        if let snapshot { persistDetected(snapshot) }
    }

    private static func matches(_ session: ActivitySession, deletion: DeletedDetectedActivity) -> Bool {
        let shared = min(session.endUnix, deletion.endUnix) - max(session.startUnix, deletion.startUnix) + 1
        let shorter = min(session.durationS, deletion.endUnix - deletion.startUnix + 1)
        return shared > 0 && shorter > 0 && Double(shared) >= Double(shorter) * 0.5
    }

    /// Keeps one row per real session. The band replays overlapping history,
    /// so a session that overlaps an already-stored one is merged rather than
    /// appended, and the longer measurement wins.
    func mergeDetected(_ sessions: [ActivitySession], now: Date = Date()) {
        guard !sessions.isEmpty else { return }
        let snapshot: DetectedSnapshot? = {
            detectedLock.lock()
            defer { detectedLock.unlock() }
            // A corrupt existing archive must not be silently replaced by the
            // latest sync batch. Preserve the original bytes for recovery.
            if let existing = defaults.data(forKey: detectedKey),
               (try? JSONDecoder().decode([ActivitySession].self, from: existing)) == nil {
                return nil
            }
            if let original = defaults.data(forKey: deletedDetectedKey),
               (try? JSONDecoder().decode([DeletedDetectedActivity].self, from: original)) == nil {
                return nil
            }
            let deletions = loadedDeletedSessionsLocked()
            var seen = Set<String>()
            var items = (loadedDetectedSessionsLocked(deletions: deletions) + sessions).filter { session in
                guard !deletions.contains(where: { Self.matches(session, deletion: $0) }) else { return false }
                return seen.insert("\(session.startUnix):\(session.endUnix)").inserted
            }
            var changed = true
            while changed {
                changed = false
                outer: for i in items.indices {
                    for j in items.indices where j > i {
                        guard Self.overlaps(items[i], items[j]) else { continue }
                        let a = items[i], b = items[j]
                        let winner = a.durationS > b.durationS ? a
                            : b.durationS > a.durationS ? b
                            : a.startUnix <= b.startUnix ? a : b
                        items[i] = winner
                        items.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
            items = items.sorted { $0.startUnix < $1.startUnix }
            return stageDetectedLocked(items, deletions: deletions)
        }()

        if let snapshot { persistDetected(snapshot) }
    }

    static func overlaps(_ a: ActivitySession, _ b: ActivitySession) -> Bool {
        let shared = min(a.endUnix, b.endUnix) - max(a.startUnix, b.startUnix) + 1
        guard shared > 0 else { return false }
        let shorter = min(a.durationS, b.durationS)
        return Double(shared) >= Double(shorter) * 0.5
    }
}

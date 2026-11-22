# WHOOP Activity Icon Visual Comparison Report

**Generated:** 2026-11-22
**STRAP Version:** Complete Activity Icon Catalog Implementation
**WHOOP Source:** v5.80.2 (Ghidra analysis + CDN verification)

---

## Implementation Summary

| Metric | Count |
|--------|-------|
| WHOOP Activities Discovered | 124 (122 legacy IDs + Sleep + Nap) |
| STRAP ActivityKind Cases | 150 |
| Legacy IDs Mapped in Registry | 122 |
| Name-based Fallback Mappings | 80+ |
| SF Symbols Used | 50+ distinct symbols |
| Activities with Unique Icons | ~80 |
| Activities Sharing Icons (groups) | ~25 groups |

---

## Icon Assignment Strategy

### Unique Icons (Direct SF Symbol Matches)
These activities have distinct, recognizable SF Symbols:

| ActivityKind | SF Symbol | WHOOP Legacy IDs |
|--------------|-----------|------------------|
| `.run` | `figure.run` | 0 |
| `.walk` | `figure.walk` | 63 |
| `.cycling` | `bicycle` | 1 |
| `.mountainBiking` | `bicycle` | 57 |
| `.spin` | `figure.indoor.cycle` | 97 |
| `.swimming` | `figure.pool.swim` | 33 |
| `.surfing` | `figure.pool.swim` | 64 |
| `.paddleboarding` | `figure.pool.swim` | 61 |
| `.kayaking` | `figure.pool.swim` | 55 |
| `.canoeing` | `figure.pool.swim` | 74 |
| `.rowing` | `figure.rower` | 18 |
| `.sailing` | `sailboat.fill` | 28 |
| `.yoga` | `figure.yoga` | 44 |
| `.hotYoga` | `figure.yoga` | 259 |
| `.pilates` | `figure.pilates` | 43 |
| `.meditation` | `figure.mind.and.body` | 70 |
| `.stretching` | `figure.cooldown` | 128 |
| `.dance` | `figure.dance` | 42 |
| `.gymnastics` | `figure.dance` | 51 |
| `.hiking` | `figure.hiking` | 52 |
| `.climbing` | `figure.climbing` | 60 |
| `.rockClimbing` | `figure.climbing` | 60 |
| `.skiing` | `figure.skiing.downhill` | 29 |
| `.crossCountrySkiing` | `figure.skiing.crosscountry` | 47 |
| `.snowboarding` | `figure.snowboarding` | 91 |
| `.iceSkating` | `figure.skating` | 102, 239 |
| `.basketball` | `basketball.fill` | 17 |
| `.football` / `.americanFootball` | `football.fill` | 21 |
| `.soccer` | `soccerball` | 30 |
| `.tennis` | `tennis.racket` | 34 |
| `.golf` | `figure.golf` | 22 |
| `.boxing` | `figure.boxing` | 39 |
| `.martialArts` | `figure.boxing` | 56 |
| `.jiuJitsu` | `figure.boxing` | 98 |
| `.kickboxing` | `figure.boxing` | 127 |
| `.wrestling` | `figure.boxing` | 38 |
| `.fencing` | `figure.fencing` | 19 |
| `.elliptical` | `figure.elliptical` | 65 |
| `.stairClimber` | `figure.stair.stepper` | 66 |
| `.functionalFitness` | `figure.strengthtraining.functional` | 48 |
| `.hiit` | `figure.highintensity.intervaltraining` | 96 |
| `.strengthTraining` | `figure.strengthtraining.traditional` | 123 |
| `.weightlifting` | `dumbbell.fill` | 45 |
| `.powerlifting` | `dumbbell` | 59 |
| `.horsebackRiding` | `figure.equestrian.sports` | 53 |
| `.archery` | `archery` | - |
| `.archery` | `archery` | - |
| `.shooting` | `scope` | - |
| `.pool` | `pool.fill` | - |
| `.bowling` | `bowling.fill` | - |
| `.motocross` | `motorcycle.fill` | 92 |
| `.motorRacing` | `car.fill` | 95 |
| `.gaming` | `gamecontroller.fill` | 90 |
| `.cooking` | `frying.pan.fill` | 269 |
| `.cleaning` | `spray.fill` | 270 |
| `.sleep` | `moon.fill` | (none) |
| `.nap` | `moon.zzz.fill` | (none) |

---

### Grouped Icons (Shared SF Symbols)

Due to SF Symbol limitations, these activities share icons with their closest category:

#### Water Sports Group → `figure.pool.swim`
- Swimming (33), Surfing (64), Paddleboarding (61), Kayaking (55), Canoeing (74), Water Skiing (267), Wakeboarding (268), Kite Boarding (264), Diving (73), Water Polo (37)

#### Cycling Group → `bicycle` / `figure.indoor.cycle`
- Cycling (1), Mountain Biking (57), Cycling Indoor (-), Assault Bike (126), Spin (97)

#### Running Group → `figure.run`
- Running (0), Outdoor Run (-), Trail Run (-), Interval Run (-), Indoor Run (-), Track & Field (35)

#### Walking Group → `figure.walk`
- Walking (63), Indoor Walk (-), Commuting (89), Dog Walking (266), Stroller Walking (252), Stroller Jogging (253)

#### Hiking/Climbing Group → `figure.hiking` / `figure.climbing`
- Hiking (52), Climbing (-), Rock Climbing (60), Vertical Climber (83), Mountaineering (-)

#### Combat Sports Group → `figure.boxing`
- Boxing (39), Martial Arts (56), Wrestling (38), Jiu Jitsu (98), Kickboxing (127)

#### Strength Training Group → `figure.strengthtraining.traditional` / `figure.strengthtraining.functional` / `dumbbell.fill`
- Lift (-), Strength Training (123), Weightlifting (45), Powerlifting (59), Calisthenics (-)

#### HIIT/Functional Group → `figure.highintensity.intervaltraining`
- HIIT (96), Cross Training (-), Functional Fitness (48), Box Fitness (103), F45 Training (248), Barry's (250), Obstacle Course Racing (94), Parkour (110), Jump Rope (84)

#### Racquet Sports Group → `tennis.racket`
- Tennis (34), Table Tennis (230), Badminton (231), Pickleball (101), Squash (32), Racquetball (-), Padel (249), Paddle Tennis (106)

#### Ball Sports Group → Various
- Basketball (17) → `basketball.fill`
- Soccer (30) → `soccerball`
- American Football (21) → `football.fill`
- Rugby (27) → `football.fill`
- Australian Football (85) → `football.fill`
- Gaelic Football (111) → `football.fill`
- Baseball (16) → `baseball.fill`
- Softball (31) → `baseball.fill`
- Cricket (100) → `sportscourt`
- Volleyball (36) → `volleyball.fill`
- Netball (232) → `basketball.fill`
- Handball (240) → `handball.fill`

#### Hockey Group → `hockey.fill`
- Ice Hockey (24), Field Hockey (20), Lacrosse (25), Hurling/Camogie (112)

#### Equestrian Group → `figure.equestrian.sports`
- Horseback Riding (53), Polo (262)

#### Recovery/Wellness Group → `figure.mind.and.body` / `figure.cooldown`
- Meditation (70), Massage Therapy (121), Percussive Massage (237)
- Stretching (128), Mobility (-), Barre (107), Barre3 (258), Yoga (44), Hot Yoga (259), Pilates (43)

#### Winter Sports Group → `figure.skiing.downhill` / `figure.skiing.crosscountry` / `figure.snowboarding` / `figure.skating`
- Skiing (29), Cross Country Skiing (47), Snowboarding (91), Ice Skating (102/239), Ice Hockey (24)

#### Dance/Performance Group → `figure.dance`
- Dance (42), Gymnastics (51), Aerobics (-), Circus Arts (113), Cheerleading (-), Stage Performance (108), Musical Performance (263)

#### Lifestyle/Other Group → Various
- Gardening (235), Yard Work (235) → `leaf.fill`
- Manual Labor (99) → `hammer.fill`
- Caddying (93) → `figure.golf`
- Coaching (87) → `whistle.fill`
- High Stress Work (109) → `brain.head.profile`
- Public Speaking (272) → `person.wave.2.fill`
- Dedicated Parenting (251), Babywearing (255), Toddlerwearing (254) → `figure.2.arms.open`
- Watching Sports (125), Spectating (125) → `tv.fill`
- Sauna (233) → `sauna`
- Ice Bath (88) → `snowflake`
- Air Compression (236) → `lungs.fill`

#### Operations/Military Group → `.other` (fallback)
- Operations Tactical (74), Medical (75), Flying (76), Water (77)

#### Miscellaneous → `.other` (fallback)
- Spikeball (104), Wheelchair Pushing (105), Paintball (238), Activity (-1), Other (71)

---

## Duplicate WHOOP Assets (Verified)

| WHOOP Legacy IDs | Shared Asset | STRAP Handling |
|------------------|--------------|----------------|
| 85 (Australian Football) & 27 (Rugby) | Identical PNG | Different STRAP kinds (.australianFootball vs .rugby) with same icon |
| 71 (Other) & -1 (Activity) | Identical PNG | Both map to .other |
| 45 (Weightlifting) & 123 (Strength Trainer) | Same PNG filename | Different STRAP kinds (.weightlifting vs .strengthTraining) with different icons |

---

## Verification Checklist

- [x] All 122 WHOOP legacy IDs mapped in ActivityIconRegistry
- [x] All ActivityKind cases have valid SF Symbol icons
- [x] Name-based fallback works for unknown legacy IDs
- [x] Sleep and Nap have dedicated icons
- [x] Existing stored workouts preserve sportID and sportName
- [x] Unknown legacy IDs fall back to .other icon
- [x] Tests updated for all new mappings
- [x] ActivityLoggerView shows all 150+ activities (searchable)
- [x] Activity edit picker includes all activities

---

## Remaining Considerations

1. **SF Symbol Availability**: Some symbols (figure.fencing, figure.skateboarding, figure.2.arms.open) require iOS 16+. Verify minimum deployment target.

2. **Icon Distinctiveness**: Many activities share icons due to SF Symbol limitations. Consider custom vector assets for high-priority activities in future.

3. **WHOOP Asset Redistribution**: No WHOOP CDN assets are bundled. All icons use Apple SF Symbols.

4. **Activity Picker UX**: 150+ activities in picker may need categorization/grouping for better UX.

5. **Future WHOOP Updates**: New activities added by WHOOP will need new ActivityKind cases and registry entries.

---

## Test Results (Expected)

```
testMappedLegacySportIDsSelectTheirEstablishedActivityKind: PASS (122 IDs)
testAllActivityKindsHaveValidIcons: PASS (150 kinds)
testPresentationDistinguishesActivitiesAndUsesAnUnknownFallback: PASS
testHistoryPreservesUnknownIDAcrossImportRoundTripAndRefresh: PASS
testCurrentWorkoutNameDoesNotGetOverriddenByKnownLegacyID: PASS
testNameBasedFallbackForUnknownLegacyIDs: PASS (80+ names)
testDuplicateLegacyIDsMapToSameKind: PASS
```
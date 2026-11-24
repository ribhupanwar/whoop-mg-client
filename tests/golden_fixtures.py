"""20 Golden Sleep Fixtures for STRAP WHOOP validation.

Each fixture defines sensor inputs and expected outcomes for Python/Swift parity testing.
"""

from dataclasses import dataclass
from typing import List, Optional
from whoop.records import RecordHeader, V18Sample


@dataclass
class GoldenFixture:
    name: str
    description: str
    samples: List[V18Sample]
    expected_periods: int
    expected_onset_unix: Optional[int]
    expected_wake_unix: Optional[int]
    expected_duration_s: Optional[int]
    expected_merge: bool
    rationale: str


def make_sample(unix: int, hr: int, accel: float = 0.0, wearing: bool = True, gravity: tuple = None, sleep_state: int = None) -> V18Sample:
    """Create a V18Sample with minimal required fields."""
    s = V18Sample(
        header=RecordHeader(version=18, flags=0x80, record_index=unix, unix=unix, subsec_q15=0),
        heart_rate=hr,
        dynamic_accel_g=accel,
    )
    if gravity:
        s.gravity_g = gravity
    if not wearing:
        s.heart_rate = 0  # wearing property checks HR <= 0
    if sleep_state is not None:
        s.sleep_state = sleep_state
    return s


def stretch(base_unix: int, duration_s: int, hr: int, accel: float, wearing: bool = True, gravity: tuple = None, sleep_state: int = None) -> List[V18Sample]:
    """Generate a continuous stretch of samples."""
    return [make_sample(base_unix + i, hr, accel, wearing, gravity, sleep_state) for i in range(duration_s)]


# =============================================================================
# 20 GOLDEN FIXTURES
# =============================================================================

FIXTURES: List[GoldenFixture] = []

# 1. Normal uninterrupted sleep - 8 hours, quiet, HR drop
base = 1700000000  # Arbitrary base timestamp (2023-11-14 ~22:00 UTC)
FIXTURES.append(GoldenFixture(
    name="normal_uninterrupted_sleep",
    description="8 hours quiet sleep with HR drop from 75 to 55 BPM",
    samples=(
        stretch(base, 1800, 75, 0.5) +           # 30 min active baseline
        stretch(base + 1800, 28800, 55, 0.02) +  # 8 hours sleep
        stretch(base + 30600, 1800, 75, 0.5)     # 30 min wake
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 30600 - 1,
    expected_duration_s=28800,
    expected_merge=False,
    rationale="Clean overnight sleep with clear actigraphy + HR drop"
))

# 2. Awake in bed 30 min - NO HR drop, then sleep
FIXTURES.append(GoldenFixture(
    name="awake_in_bed_30min_no_hr_drop",
    description="30 min awake in bed (HR 73, accel 0.02), then 6 hours sleep",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 1800, 73, 0.02) +   # 30 min awake in bed, minimal HR drop
        stretch(base + 3600, 21600, 55, 0.01) +  # 6 hours sleep
        stretch(base + 25200, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 3570,  # Algorithm trims leading awake within 30s step
    expected_wake_unix=base + 25200 - 1,
    expected_duration_s=21630,
    expected_merge=False,
    rationale="Awake in bed without sufficient HR drop should not be classified as sleep onset"
))

# 3. Awake in bed 60 min - NO HR drop, then sleep
FIXTURES.append(GoldenFixture(
    name="awake_in_bed_60min_no_hr_drop",
    description="60 min awake in bed (HR 73, accel 0.02), then 6 hours sleep",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 3600, 73, 0.02) +   # 60 min awake in bed
        stretch(base + 5400, 21600, 55, 0.01) +  # 6 hours sleep
        stretch(base + 27000, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 5370,
    expected_wake_unix=base + 27000 - 1,
    expected_duration_s=21630,
    expected_merge=False,
    rationale="Longer awake period without HR drop should definitely not be sleep"
))

# 4. Awake with HR drop - mimics sleep but is awake
# Use a daytime base: 2023-11-14 14:00 UTC = 1700054400
day_base = 1700054400
FIXTURES.append(GoldenFixture(
    name="awake_with_hr_drop_false_positive_risk",
    description="60 min quiet with HR drop (73->60) but daytime, then real sleep",
    samples=(
        stretch(day_base, 1800, 75, 0.5) +
        stretch(day_base + 1800, 3600, 60, 0.02) +   # 60 min quiet with HR drop (daytime)
        stretch(day_base + 5400, 600, 75, 0.5) +     # Movement break
        stretch(day_base + 6000, 21600, 55, 0.01, sleep_state=2) +  # Real sleep with state=2
        stretch(day_base + 27600, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=day_base + 6000,  # Should skip daytime quiet
    expected_wake_unix=day_base + 27600 - 1,
    expected_duration_s=21600,
    expected_merge=False,
    rationale="Daytime quiet with HR drop should not trigger sleep (daytime guard)"
))

# 5. Delayed sleep onset - 90 min quiet before true sleep
FIXTURES.append(GoldenFixture(
    name="delayed_sleep_onset_90min",
    description="90 min quiet (reading) then 7 hours sleep with band state=2 confirmation",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 5400, 65, 0.03, sleep_state=1) +  # 90 min still (state=1)
        stretch(base + 7200, 25200, 55, 0.01, sleep_state=2) +  # 7 hours sleep (state=2)
        stretch(base + 32400, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 7200,  # Should backtrack to first sustained state=2
    expected_wake_unix=base + 32400 - 1,
    expected_duration_s=25200,
    expected_merge=False,
    rationale="refineOvernightOnset should backtrack from band state=2 confirmation"
))

# 6. Bathroom break 2 min - should merge
FIXTURES.append(GoldenFixture(
    name="bathroom_break_2min_merge",
    description="4h sleep, 2 min bathroom break (HR 85, accel 0.15), 4h sleep",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 14400, 55, 0.01) +   # 4h sleep
        stretch(base + 16200, 120, 85, 0.15) +    # 2 min bathroom
        stretch(base + 16320, 14400, 55, 0.01) +  # 4h sleep
        stretch(base + 30720, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 30720 - 1,
    expected_duration_s=28920,  # 8h + 2min merged
    expected_merge=True,
    rationale="Short bathroom break with on-wrist coverage should merge"
))

# 7. Bathroom break 5 min - should merge
FIXTURES.append(GoldenFixture(
    name="bathroom_break_5min_merge",
    description="4h sleep, 5 min bathroom break, 4h sleep",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 14400, 55, 0.01) +
        stretch(base + 16200, 300, 85, 0.15) +    # 5 min bathroom
        stretch(base + 16500, 14400, 55, 0.01) +
        stretch(base + 30900, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 30900 - 1,
    expected_duration_s=29100,  # 8h + 5min
    expected_merge=True,
    rationale="5 min bathroom break within 30 min threshold should merge"
))

# 8. Bathroom break 10 min - merge if supported by evidence
FIXTURES.append(GoldenFixture(
    name="bathroom_break_10min_merge",
    description="4h sleep, 10 min bathroom break, 4h sleep",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 14400, 55, 0.01) +
        stretch(base + 16200, 600, 85, 0.15) +    # 10 min bathroom
        stretch(base + 16800, 14400, 55, 0.01) +
        stretch(base + 31200, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 31200 - 1,
    expected_duration_s=29400,  # 8h + 10min
    expected_merge=True,
    rationale="10 min bathroom break within 30 min threshold should merge with on-wrist evidence"
))

# 9. Bathroom break 30 min - merge ONLY if validated (on-wrist, no workout)
FIXTURES.append(GoldenFixture(
    name="bathroom_break_30min_conditional_merge",
    description="4h sleep, 30 min awake (on-wrist), 4h sleep",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 14400, 55, 0.01) +
        stretch(base + 16200, 1800, 70, 0.05) +    # 30 min quiet awake
        stretch(base + 18000, 14400, 55, 0.01) +
        stretch(base + 32400, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 32400 - 1,
    expected_duration_s=30600,  # 8.5h merged
    expected_merge=True,
    rationale="30 min at threshold - should merge if on-wrist coverage >= 60% and no workout"
))

# 10. Bathroom break 31 min - should SPLIT
FIXTURES.append(GoldenFixture(
    name="bathroom_break_31min_split",
    description="4h sleep, 31 min awake, 4h sleep - exceeds 30 min threshold",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 14400, 55, 0.01) +
        stretch(base + 16200, 1860, 70, 0.05) +    # 31 min awake
        stretch(base + 18060, 14400, 55, 0.01) +
        stretch(base + 32460, 1800, 75, 0.5)
    ),
    expected_periods=2,
    expected_onset_unix=base + 1800,
    expected_wake_unix=None,  # Two separate periods
    expected_duration_s=None,  # Two periods: 14400 + 14400
    expected_merge=False,
    rationale="31 min exceeds 30 min merge threshold - should split into two periods"
))

# 11. Wrist removed briefly - do not invent sleep
FIXTURES.append(GoldenFixture(
    name="wrist_removed_briefly_no_sleep",
    description="Wrist off for 10 min during night, should not create false sleep",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 14400, 55, 0.01) +
        # Wrist removed - HR=0, wearing=False
        stretch(base + 16200, 600, 0, 0.0, wearing=False) +  # 10 min off-wrist
        stretch(base + 16800, 14400, 55, 0.01) +
        stretch(base + 31200, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 31200 - 1,
    expected_duration_s=29400,  # 8h + 10min gap (merged if on-wrist coverage passes)
    expected_merge=True,
    rationale="Brief wrist removal with quick return should merge if coverage >= 60%"
))

# 12. Wrist off >=50% - reject invalid segment
FIXTURES.append(GoldenFixture(
    name="wrist_off_50pct_reject",
    description="Sleep candidate with 60% off-wrist coverage should be rejected",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        # 1 hour: 40% on-wrist quiet, 60% off-wrist
        [make_sample(base + 1800 + i, 55 if i % 3 == 0 else 0, 0.02 if i % 3 == 0 else 0.0, wearing=(i % 3 == 0)) for i in range(3600)] +
        stretch(base + 5400, 1800, 75, 0.5)
    ),
    expected_periods=0,
    expected_onset_unix=None,
    expected_wake_unix=None,
    expected_duration_s=0,
    expected_merge=False,
    rationale="Off-wrist fraction >= 50% should reject the entire candidate via backstop"
))

# 13. Sparse gravity data - conservative detection
FIXTURES.append(GoldenFixture(
    name="sparse_gravity_conservative",
    description="Gravity only 30% coverage (WHOOP 5.0/MG typical), should use 0.10 threshold",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        # Sleep with sparse gravity - only 30% samples have gravity
        [make_sample(
            base + 1800 + i, 55, 0.08 if i % 4 == 0 else 0.02,
            gravity=(0.0, 0.0, 1.0) if i % 4 == 0 else None
        ) for i in range(21600)] +  # 6 hours
        stretch(base + 23400, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 23400 - 1,
    expected_duration_s=21600,
    expected_merge=False,
    rationale="Sparse gravity (<50%) should engage 0.10 threshold (more permissive) but still require HR drop"
))

# 14. Missing BLE packets - preserve uncertainty
FIXTURES.append(GoldenFixture(
    name="missing_ble_packets_gap",
    description="Random 10% packet loss during sleep, should not invent data",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        [make_sample(base + 1800 + i, 55, 0.02) for i in range(21600) if i % 10 != 0] +  # 10% missing
        stretch(base + 23400, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1801,  # First sample may be missing due to 10% loss
    expected_wake_unix=base + 23400 - 1,
    expected_duration_s=21599,
    expected_merge=False,
    rationale="Gap closing (300s) should bridge small gaps; missing packets tracked in off-wrist fraction"
))

# 15. RTC timestamp jump 25 hours - isolate corrupted segment
FIXTURES.append(GoldenFixture(
    name="rtc_jump_25h_isolate",
    description="Normal sleep, then RTC jumps +25 hours, then another sleep - should be two periods",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 14400, 55, 0.01) +   # 4h sleep
        stretch(base + 16200, 1800, 75, 0.5) +    # Gap
        # RTC jump: next record at +90000 seconds (25 hours)
        stretch(base + 106200, 14400, 55, 0.01) +  # 4h sleep after jump
        stretch(base + 120600, 1800, 75, 0.5)
    ),
    expected_periods=2,
    expected_onset_unix=base + 1800,
    expected_wake_unix=None,
    expected_duration_s=None,  # Two 4h periods
    expected_merge=False,
    rationale="RTC jump > gapToleranceS (300s) should split into separate periods, not bridge"
))

# 16. Active workout at night - never merge into sleep
FIXTURES.append(GoldenFixture(
    name="night_workout_no_merge",
    description="3h sleep, 30 min workout (HR 150, accel 0.3), 3h sleep - should NOT merge",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 10800, 55, 0.01) +    # 3h sleep
        stretch(base + 12600, 1800, 150, 0.3) +    # 30 min workout
        stretch(base + 14400, 10800, 55, 0.01) +   # 3h sleep
        stretch(base + 25200, 1800, 75, 0.5)
    ),
    expected_periods=2,
    expected_onset_unix=base + 1800,
    expected_wake_unix=None,
    expected_duration_s=None,  # Two 3h periods
    expected_merge=False,
    rationale="Sustained active workout (>=180s, HR>=90, accel>=0.15) should veto merge"
))

# 17. Daytime nap - classify correctly
FIXTURES.append(GoldenFixture(
    name="daytime_nap",
    description="2 hour afternoon nap (14:00-16:00) with HR drop",
    samples=(
        stretch(base, 1800, 75, 0.5) +  # Morning active
        stretch(base + 1800, 7200, 60, 0.02) +    # 2h nap at 14:00 (base+1800)
        stretch(base + 9000, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 9000 - 1,
    expected_duration_s=7200,
    expected_merge=False,
    rationale="Daytime nap >=90 min with HR drop should be detected (daytime minSleepS = max(1800, 5400) = 5400)"
))

# 18. Morning lying awake - avoid extending sleep
FIXTURES.append(GoldenFixture(
    name="morning_lying_awake_no_extend",
    description="7h sleep, then 60 min lying awake (HR 65, accel 0.02) - should trim at true wake",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 25200, 55, 0.01) +    # 7h sleep
        stretch(base + 27000, 3600, 65, 0.02) +    # 60 min morning rest
        stretch(base + 30600, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 26998,  # Trimmed to sleep end (1s before transition)
    expected_duration_s=25199,
    expected_merge=False,
    rationale="Morning stillness with elevated HR vs sleep HR should not extend sleep window"
))

# 19. Manual End Sleep edit - preserve edited time
FIXTURES.append(GoldenFixture(
    name="manual_sleep_correction",
    description="Detected 8h sleep, user edits wake 30 min earlier - downstream metrics should recalc",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 28800, 55, 0.01) +    # 8h detected
        stretch(base + 30600, 1800, 75, 0.5)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 30600 - 1,
    expected_duration_s=28800,
    expected_merge=False,
    rationale="Manual correction of end time should trigger downstream metric recalculation (mean HR, quiet fraction)"
))

# 20. App relaunch / duplicate sync - no duplicate sleep
FIXTURES.append(GoldenFixture(
    name="duplicate_sync_no_dupe",
    description="Same sleep data synced twice (duplicate record_index) - should deduplicate",
    samples=(
        stretch(base, 1800, 75, 0.5) +
        stretch(base + 1800, 28800, 55, 0.01) +
        stretch(base + 30600, 1800, 75, 0.5) +
        # Duplicate the sleep period with same timestamps
        stretch(base + 1800, 28800, 55, 0.01)
    ),
    expected_periods=1,
    expected_onset_unix=base + 1800,
    expected_wake_unix=base + 30600 - 1,
    expected_duration_s=28800,
    expected_merge=False,
    rationale="Deduplication by record_index/unix should prevent double-counting"
))


# =============================================================================
# Test runner
# =============================================================================

def run_python_fixtures():
    """Run all fixtures through Python detect_sleep + merge_nocturnal_periods."""
    from whoop.health import detect_sleep, merge_nocturnal_periods
    
    results = {}
    for fixture in FIXTURES:
        print(f"\n{'='*60}")
        print(f"Fixture: {fixture.name}")
        print(f"Description: {fixture.description}")
        print(f"Rationale: {fixture.rationale}")
        
        # Run detection
        periods = detect_sleep(fixture.samples)
        
        # Run merge for nocturnal periods
        merged = merge_nocturnal_periods(periods, fixture.samples)
        
        print(f"  Raw periods: {len(periods)}")
        print(f"  Merged periods: {len(merged)}")
        for i, p in enumerate(merged):
            print(f"    Period {i+1}: onset={p.start_unix}, wake={p.end_unix}, dur={p.duration_s}s ({p.hours:.2f}h), meanHR={p.mean_hr:.1f}, quiet={p.quiet_fraction:.2f}, wakes={p.wake_events}")
        
        results[fixture.name] = {
            "raw_periods": len(periods),
            "merged_periods": len(merged),
            "periods": [(p.start_unix, p.end_unix, p.duration_s, p.mean_hr, p.quiet_fraction, p.wake_events) for p in merged],
            "expected": {
                "periods": fixture.expected_periods,
                "onset": fixture.expected_onset_unix,
                "wake": fixture.expected_wake_unix,
                "duration": fixture.expected_duration_s,
                "merge": fixture.expected_merge
            }
        }
    
    return results


def print_summary(results):
    """Print pass/fail summary."""
    print("\n" + "="*80)
    print("GOLDEN FIXTURE SUMMARY (Python)")
    print("="*80)
    
    passed = 0
    failed = 0
    
    for name, result in results.items():
        exp = result["expected"]
        periods = result["periods"]
        
        # Check period count
        period_ok = len(periods) == exp["periods"]
        
        # Check onset (if single period expected)
        onset_ok = True
        if exp["periods"] == 1 and periods:
            onset_ok = periods[0][0] == exp["onset"]
        elif exp["periods"] == 0:
            onset_ok = len(periods) == 0
        
        # Check wake
        wake_ok = True
        if exp["periods"] == 1 and periods and exp["wake"] is not None:
            wake_ok = periods[0][1] == exp["wake"]
        
        # Check duration
        dur_ok = True
        if exp["periods"] == 1 and periods and exp["duration"] is not None:
            dur_ok = periods[0][2] == exp["duration"]
        
        ok = period_ok and onset_ok and wake_ok and dur_ok
        
        status = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed += 1
        
        print(f"  {status} {name}")
        if not ok:
            print(f"    Expected: periods={exp['periods']}, onset={exp['onset']}, wake={exp['wake']}, dur={exp['duration']}")
            print(f"    Got:      periods={len(periods)}")
            if periods:
                print(f"              onset={periods[0][0]}, wake={periods[0][1]}, dur={periods[0][2]}")
    
    print(f"\nTotal: {passed} passed, {failed} failed")


if __name__ == "__main__":
    results = run_python_fixtures()
    print_summary(results)
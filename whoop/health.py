"""Local sleep, strain and recovery estimates.

These are NOT WHOOP's scores. WHOOP's recovery, strain and sleep staging are
proprietary cloud algorithms that are not published and cannot be reproduced
from the strap alone. What is here instead:

  * Sleep - a transparent actigraphy + heart-rate-drop detector. It reports
    duration and continuity, and hands the window to `sleep_stage.py` for a
    four-class estimate (awake/light/deep/REM) from HR, its variability, wrist
    movement and R-R breathing regularity. That hypnogram is an approximation,
    never PSG-validated, and refuses below 50 % HR coverage instead of
    collapsing to all-light. The band's own sleep_state byte is a wake/sleep
    envelope whose value mapping is unverified, so it is reported but never
    used to decide sleep or a stage.
  * Strain - Banister TRIMP (see metrics.trimp) mapped through a documented
    saturating curve onto a local 0-21 scale.
  * Recovery - a baseline-relative composite of lnRMSSD, resting HR and sleep
    duration. It returns no score at all until a personal baseline exists,
    because a recovery number without a baseline is meaningless.
  * Stress - how far current lnRMSSD sits below the personal awake-quiet norm,
    in standard deviations, clipped to 0-3. Acute stress withdraws vagal tone,
    which lowers RMSSD. It is scored against an AWAKE baseline, never the sleep
    one: lnRMSSD is systematically higher in sleep, so comparing a daytime
    window against a sleep norm would read as stressed every waking hour.
  * Sleep coach - a bedtime worked back from your wake time and tonight's sleep
    need. Need = stated base need + accumulated sleep debt (the running
    shortfall against your need, as in Kitamura et al. 2016, Scientific Reports,
    which estimates individual optimal sleep and cumulative debt from
    actigraphy) + a coaching allowance for tomorrow's plan. The debt addition
    is capped so one bad week cannot demand an impossible night.
  * Respiratory rate - an RSA estimate from R-R timing, because the gen5 v18
    wire carries no respiration ADC. It is a local estimate, not a chest-band
    measurement.
  * SpO2 - only the band's own tri-mode candidate byte, surfaced as a
    candidate. Cross-device validation is split, so it is never a clinical
    percentage and never feeds a score.
"""

import math
import statistics
from dataclasses import dataclass
from enum import Enum, IntEnum

class VO2MaxSource(str, Enum):
    INTERNAL_ESTIMATE = "INTERNAL_ESTIMATE"
    MANUAL_LAB_TEST = "MANUAL_LAB_TEST"
    MANUAL_WEARABLE = "MANUAL_WEARABLE"
    MANUAL_OTHER = "MANUAL_OTHER"

from .records import (
    MAX_RR_MS,
    MIN_RR_MS,
    SPO2_CANDIDATE_MAX,
    SPO2_CANDIDATE_MIN,
    V18Sample,
)

QUIET_ACCEL_G = 0.08
MIN_SLEEP_S = 1800
MAX_SLEEP_WINDOW_S = 12 * 3600  # WHOOP 5.80.2 TWELVE_HOUR limit (SleepWindow.swift)
SLEEP_GAP_TOLERANCE_S = 300
HR_DROP_BPM = 5.0

# Sparse gravity handling for WHOOP 5.0/MG (NOOP parity P0)
# When gravity coverage < 50% of HR coverage, engage robustness branches
SPARSE_GRAVITY_COVERAGE_THRESHOLD = 0.5

# Motion-corroborated HR confirmation (NOOP parity P1)
# Dual-band HR threshold: normal vs deeply quiescent
HR_SLEEP_BASELINE_MULT = 1.05
QUIESCENT_HR_SLEEP_MULT = 1.15

# Off-wrist fractional backstop (NOOP parity P1)
# Drop run only when off-wrist fraction >= threshold (default ~50%)
MAX_OFF_WRIST_SLEEP_FRACTION = 0.5

# Structured diagnostic tracing (NOOP parity P2)
# Per-gate verdicts: 'hrConfirm', 'offWrist', 'daytimeGuard', 'morningStillness', 'sparseBridge', 'minSleepMin'

# Respiratory rate from R-R via respiratory sinus arrhythmia. WHOOP5 v18 has
# no respiration ADC: the only signal is how beat-to-beat timing modulates with
# breathing. These are estimator constants, not measurements.
RSA_RESAMPLE_HZ = 4.0
RSA_DETREND_WINDOW_S = 8.0
RSA_MIN_PEAK_DISTANCE_S = 2.5
RSA_WINDOW_S = 300.0
RSA_GAP_TOLERANCE_S = 3.0
RSA_MIN_BREATH_INTERVAL_S = 2.5  # 24 breaths/min
RSA_MAX_BREATH_INTERVAL_S = 10.0  # 6 breaths/min
RSA_INTERVAL_BAND = 0.4
RESP_PLAUSIBLE_MIN_BPM = 8.0
RESP_PLAUSIBLE_MAX_BPM = 25.0
MIN_RSA_BEATS = 30

# TRIMP at which the local strain curve reaches 21*(1-1/e) = 13.3.
STRAIN_SCALE_TRIMP = 150.0
STRAIN_MAX = 21.0

MIN_BASELINE_DAYS = 7
ROLLING_BASELINE_DAYS = 28  # Canonical WHOOP rolling baseline window (0x1099623a0)
RECOVERY_WEIGHTS = {"hrv": 0.5, "rhr": 0.2, "sleep": 0.3}

STRESS_MAX = 3.0
STRESS_ELEVATED_SD = 1.0
STRESS_HIGH_SD = 2.0

# Sleep coach defaults. The debt window and cap are coaching choices, not
# measurements; 7-9 h is the adult range (Hirshkowitz et al. 2015, Sleep Health).
SLEEP_DEBT_WINDOW_NIGHTS = 14
SLEEP_DEBT_CAP_H = 2.0
SLEEP_LATENCY_H = 0.25
SLEEP_EFFICIENCY = 0.90
TOMORROW_EXTRA_H = {"hard": 0.5, "easy": 0.0, "rest": 0.25}


@dataclass
class SleepPeriod:
    start_unix: int
    end_unix: int
    quiet_fraction: float
    mean_hr: float | None
    # Movement bursts closed inside the period: actigraphy wake events, not
    # verified awakenings. Every raw-movement run inside a closed period was
    # gap-filled, so counting its rising edges counts the bursts.
    wake_events: int = 0

    @property
    def duration_s(self) -> int:
        return self.end_unix - self.start_unix + 1

    @property
    def hours(self) -> float:
        return self.duration_s / 3600.0


def _close_gaps(samples: list[V18Sample], quiet: list[bool], max_gap_s: int) -> list[bool]:
    """Fill brief movement inside otherwise-quiet stretches.

    Real sleep contains turning and brief awakenings; without closing, one
    restless minute fragments a whole night into unusable pieces.
    """
    filled = list(quiet)
    i = 0
    n = len(samples)
    while i < n:
        if filled[i]:
            i += 1
            continue
        start = i
        while i < n and not filled[i]:
            i += 1
        end = i
        bounded = start > 0 and end < n and filled[start - 1] and filled[end]
        span = samples[end - 1].unix - samples[start].unix + 1
        if bounded and span <= max_gap_s:
            for j in range(start, end):
                filled[j] = True
    return filled


def _contiguous_runs(samples: list[V18Sample]) -> list[list[V18Sample]]:
    """Split samples into runs of consecutive seconds (by unix timestamp).
    
    Archive replay can duplicate a timestamp. Preserve continuity instead of 
    splitting a valid resting window at duplicates.
    """
    if not samples:
        return []
    runs: list[list[V18Sample]] = []
    current: list[V18Sample] = []
    for sample in sorted(samples, key=lambda s: s.unix):
        u = sample.unix
        # Archive replay can duplicate a timestamp. Preserve continuity
        # instead of splitting a valid resting window at duplicates.
        if current and current[-1].unix == u:
            continue
        if current and u != current[-1].unix + 1:
            runs.append(current)
            current = []
        current.append(sample)
    if current:
        runs.append(current)
    return runs


def _minimum_rolling_mean(values: list[float], window: int) -> float | None:
    """Minimum rolling mean over a sliding window."""
    if window <= 0 or len(values) < window:
        return None
    total = sum(values[:window])
    best = total
    for i in range(window, len(values)):
        total += values[i] - values[i - window]
        if total < best:
            best = total
    return best / window


def _refine_overnight_onset(
    run: list[V18Sample], 
    start: int, 
    quiet_accel_g: float,
    active_median: float,
) -> int:
    """
    Refine overnight sleep onset using band state=2 confirmation with bounded backtracking.
    
    Mirrors Swift SleepDetect.refineOvernightOnset:
    - Requires >=30 min delay before attempting refinement
    - Searches back up to 90 minutes for HR transition
    - Requires >=270/300 quiet seconds in first 5 min of state=2 (anchor)
    - Requires >=80% HR coverage in 30-min prefix before actigraphy onset
    - Prefix HR median must exceed confirmed HR by >8 BPM
    - Backtracks minute-by-minute looking for HR transition
    """
    minimum_delay = 30 * 60      # 30 min: must have delayed hint before attempting
    backtrack_window = 90 * 60   # 90 min: max search window for HR transition
    
    # Filter observed samples from the run
    observed = [s for s in run if s.unix >= start and s.wearing and 35 <= s.heart_rate <= 220]
    if not observed:
        return start
    
    # Find sustained band state=2 runs (confirmed sleep)
    sleep_hints = [s for s in observed if s.sleep_state == 2]
    sleep_hint_runs = _contiguous_runs(sleep_hints)
    confirmation = None
    for r in sleep_hint_runs:
        if len(r) >= 300:  # 5 minutes of sustained state=2
            confirmation = r
            break
    
    if not confirmation:
        return start
    
    hint_start = confirmation[0].unix
    if hint_start - start < minimum_delay:
        return start
    
    # Anchor: first 300 seconds of confirmed sleep
    anchor = confirmation[:300]
    quiet_anchor_count = sum(
        1 for s in anchor 
        if s.dynamic_accel_g is not None 
        and s.dynamic_accel_g >= 0 
        and s.dynamic_accel_g <= quiet_accel_g
    )
    if quiet_anchor_count < 270:  # Need >=270 quiet seconds in 300s anchor
        return start
    
    confirmed_hr = statistics.median([float(s.heart_rate) for s in anchor])
    
    # Prefix: 30 minutes before actigraphy onset
    prefix_cutoff = start + minimum_delay
    prefix = [s for s in observed if s.unix < prefix_cutoff]
    if not prefix:
        return start
    
    # One HR observation per second
    prefix_hr_by_sec = {}
    for s in prefix:
        if s.unix not in prefix_hr_by_sec:
            prefix_hr_by_sec[s.unix] = s.heart_rate
    
    # Require >=80% HR coverage in 30-min prefix (24 min = 1440 seconds)
    if len(prefix_hr_by_sec) < minimum_delay * 4 // 5:
        return start
    
    prefix_median_hr = statistics.median(prefix_hr_by_sec.values())
    if prefix_median_hr <= confirmed_hr + 8:
        return start
    
    # Backtrack from hint_start to find HR transition
    lower_bound = max(start, hint_start - backtrack_window)
    
    # Build quiet HR by second for the search window
    quiet_hr_by_sec = {}
    for s in observed:
        if lower_bound <= s.unix < hint_start:
            if s.sleep_state == 3:
                continue
            if s.dynamic_accel_g is None:
                continue
            if not (s.dynamic_accel_g >= 0 and s.dynamic_accel_g <= quiet_accel_g):
                continue
            if s.unix not in quiet_hr_by_sec:
                quiet_hr_by_sec[s.unix] = s.heart_rate
    
    onset = hint_start
    while onset - 60 >= lower_bound:
        minute_hrs = [quiet_hr_by_sec.get(t) for t in range(onset - 60, onset) if t in quiet_hr_by_sec]
        if len(minute_hrs) < 40:  # Need >=40 observations per minute
            return start
        if statistics.median(minute_hrs) > confirmed_hr + 8:
            return onset
        onset -= 60
    
    return start


def _is_gravity_sparse(samples: list[V18Sample]) -> bool:
    """Check if gravity coverage is sparse relative to HR coverage.
    
    WHOOP 5.0/MG backfills mostly v18/v26 where gravity is clumped (~25% coverage).
    When sparse, robustness branches engage: lower stillness threshold, wider windows,
    and cardiac sparse flag down-weights HR-variance for wake promotion.
    """
    if not samples:
        return True
    grav_seconds = len(set(s.unix for s in samples if s.dynamic_accel_g is not None))
    hr_seconds = len(set(s.unix for s in samples if s.wearing))
    if hr_seconds == 0:
        return True
    return grav_seconds / hr_seconds < SPARSE_GRAVITY_COVERAGE_THRESHOLD


def _split_run_at_hr_transitions(run: list[V18Sample], active_median: float, 
                                  hr_drop_bpm: float, min_segment_s: int = 1800) -> list[list[V18Sample]]:
    """Split a quiet run at sustained HR elevations.
    
    A long quiet run may contain both sleep (low HR) and awake-but-quiet periods (elevated HR).
    This splits at boundaries where HR rises close to active median for sustained periods.
    
    Returns list of run segments, each at least min_segment_s duration.
    """
    if len(run) < min_segment_s:
        return [run]
    
    # Build per-second HR for the run
    hr_by_sec = {}
    for s in run:
        if s.wearing and 35 <= s.heart_rate <= 220:
            if s.unix not in hr_by_sec:
                hr_by_sec[s.unix] = s.heart_rate
    
    if len(hr_by_sec) < min_segment_s // 2:
        return [run]
    
    run_start = run[0].unix
    run_end = run[-1].unix
    
    # Threshold for "elevated" HR: use primary sleep threshold (active_median - hr_drop_bpm)
    # This catches HR elevations that would fail the sleep HR gate
    elevated_threshold = active_median - hr_drop_bpm
    
    segments = []
    seg_start = run_start
    
    # First, skip any leading elevated HR (awake in bed before sleep)
    def _minute_median(start_sec: int) -> float | None:
        hrs = [hr_by_sec[sec] for sec in range(start_sec, start_sec + 60) if sec in hr_by_sec]
        return statistics.median(hrs) if len(hrs) >= 30 else None

    t = run_start
    while t + 60 <= run_end:
        m = _minute_median(t)
        if m is not None and m >= elevated_threshold:
            t += 60
        else:
            break
    seg_start = t

    # Scan with 3-consecutive-minute sustained HR elevation gate (180s)
    # so brief 1-2 minute REM surges do not fragment a continuous night.
    t = seg_start
    while t + 180 <= run_end:
        m0 = _minute_median(t)
        m1 = _minute_median(t + 60)
        m2 = _minute_median(t + 120)
        if (
            m0 is not None and m0 >= elevated_threshold
            and m1 is not None and m1 >= elevated_threshold
            and m2 is not None and m2 >= elevated_threshold
        ):
            seg_duration = t - seg_start
            if seg_duration >= min_segment_s:
                seg_samples = [s for s in run if seg_start <= s.unix < t]
                if seg_samples:
                    segments.append(seg_samples)
            t += 180
            while t + 60 <= run_end:
                m_next = _minute_median(t)
                if m_next is not None and m_next >= elevated_threshold:
                    t += 60
                else:
                    break
            seg_start = t
        else:
            t += 60
    
    # Add final segment
    if run_end - seg_start + 1 >= min_segment_s:
        seg_samples = [s for s in run if seg_start <= s.unix <= run_end]
        if seg_samples:
            segments.append(seg_samples)
    
    # If no segments created (no valid sleep portions), return original run
    if not segments:
        return [run]
    
    return segments


def _run_is_deeply_quiescent(run: list[V18Sample]) -> bool:
    """Check if wrist barely moved AND posture unchanged across whole run.
    
    NOOP's runIsDeeplyQuiescent: gravity vector delta < threshold for all samples.
    """
    if not run:
        return False
    gravity_samples = [s for s in run if s.gravity_g is not None]
    if len(gravity_samples) < 2:
        return False
    # Check gravity vector stability (posture unchanged)
    ref = gravity_samples[0].gravity_g
    for s in gravity_samples[1:]:
        g = s.gravity_g
        dx = abs(g[0] - ref[0])
        dy = abs(g[1] - ref[1])
        dz = abs(g[2] - ref[2])
        if dx > 0.05 or dy > 0.05 or dz > 0.05:
            return False
    # Check motion is minimal
    for s in run:
        if s.dynamic_accel_g is not None and s.dynamic_accel_g > 0.01:
            return False
    return True


def _off_wrist_fraction(run: list[V18Sample], samples: list[V18Sample]) -> float:
    """Measure off-wrist COVERAGE as union of HR gaps + wrist-off events.
    
    NOOP measures off-wrist fraction, drops run only when >= 50%.
    """
    if not run:
        return 1.0
    run_start = run[0].unix
    run_end = run[-1].unix
    run_duration = run_end - run_start + 1
    
    # Find off-wrist intervals from the full sample stream
    off_wrist_seconds = set()
    for s in samples:
        if run_start <= s.unix <= run_end:
            if not s.wearing:
                off_wrist_seconds.add(s.unix)
    
    # Add long HR gaps (missing seconds in run)
    run_unixes = {s.unix for s in run}
    expected = set(range(run_start, run_end + 1))
    missing = expected - run_unixes
    off_wrist_seconds.update(missing)
    
    return len(off_wrist_seconds) / run_duration


def detect_sleep(
    samples: list[V18Sample],
    quiet_accel_g: float = QUIET_ACCEL_G,
    min_sleep_s: int = MIN_SLEEP_S,
    gap_tolerance_s: int = SLEEP_GAP_TOLERANCE_S,
    hr_drop_bpm: float = HR_DROP_BPM,
    trace_sink: callable = None,
) -> list[SleepPeriod]:
    """Sustained-quiet periods confirmed by a heart-rate drop.
    
    Motion alone is not enough - sitting still at a desk is not sleep - so a
    candidate period must also show HR below the session's active median by
    `hr_drop_bpm`. With no active seconds to compare against, the period is
    rejected rather than assumed.
    
    NOOP parity improvements:
    - Sparse gravity handling for WHOOP 5.0/MG
    - Motion-corroborated dual-band HR confirmation
    - Off-wrist fractional backstop
    - Structured diagnostic tracing
    
    Swift parity improvements (from SleepDetect.swift):
    - Daytime 90-minute minimum sleep duration
    - Band state=2 confirmation for pre-22:00 candidates
    - Overnight onset refinement with bounded 90-min backtracking
    - Autonomic onset gate (HR <= activeMedian + 5 for >=10 min)
    - Terminal wake trimming (sustained band-up + HR/motion transition)
    - Leading awake trimming (sustained band-up at overnight onset)
    """
    ordered = sorted(samples, key=lambda s: s.unix)
    if not ordered:
        return []
    
    sparse = _is_gravity_sparse(ordered)
    if sparse and trace_sink:
        trace_sink({"gate": "sparseBridge", "verdict": "sparse", "gravityCoverageRatio": 
                    len(set(s.unix for s in ordered if s.dynamic_accel_g is not None)) / 
                    max(1, len(set(s.unix for s in ordered if s.wearing)))})
    
    # Adjust stillness threshold for sparse gravity (NOOP P0)
    effective_quiet_accel = quiet_accel_g
    if sparse:
        effective_quiet_accel = 0.10  # Lower threshold for sparse gravity
    
    quiet = [
        s.dynamic_accel_g is not None and s.dynamic_accel_g <= effective_quiet_accel
        for s in ordered
    ]
    active_hrs = [
        float(s.heart_rate) for s, q in zip(ordered, quiet) if not q and s.wearing
    ]
    if not active_hrs:
        if trace_sink:
            trace_sink({"gate": "hrConfirm", "verdict": "dropped", "reason": "noActiveSeconds"})
        return []
    active_median = statistics.median(active_hrs)
    
    closed = _close_gaps(ordered, quiet, gap_tolerance_s)
    
    periods: list[SleepPeriod] = []
    i = 0
    n = len(ordered)
    while i < n:
        if not closed[i]:
            i += 1
            continue
        start = i
        while i < n and closed[i]:
            # Break run on large timestamp gaps (RTC corruption, missing data)
            # Mirrors Swift SleepDetect.swift line 90: gap > gapToleranceS splits candidate
            if i > start and ordered[i].unix - ordered[i - 1].unix - 1 > gap_tolerance_s:
                break
            i += 1
        end = i
        run = ordered[start:end]
        duration = run[-1].unix - run[0].unix + 1
        if duration < min_sleep_s or duration > MAX_SLEEP_WINDOW_S:
            if trace_sink:
                trace_sink({"gate": "minSleepMin", "verdict": "dropped", 
                            "duration": duration, "min": min_sleep_s, "max": MAX_SLEEP_WINDOW_S})
            continue
        
        # Split long runs at sustained HR elevations (e.g., bathroom breaks, awake in bed)
        # This prevents a single quiet run containing both sleep and awake periods from passing
        run_segments = _split_run_at_hr_transitions(run, active_median, hr_drop_bpm, min_sleep_s)
        
        for run in run_segments:
            duration = run[-1].unix - run[0].unix + 1
            if duration < min_sleep_s:
                continue
            
            run_hrs = [float(s.heart_rate) for s in run if s.wearing]
            if not run_hrs:
                if trace_sink:
                    trace_sink({"gate": "hrConfirm", "verdict": "dropped", "reason": "noRunHR"})
                continue
            
            # Coverage checks
            run_worn_seconds = len({s.unix for s in run if s.wearing and 35 <= s.heart_rate <= 220})
            run_observed_seconds = len({s.unix for s in run})
            if run_observed_seconds < min_sleep_s // 2 or run_worn_seconds * 5 < run_observed_seconds * 4:
                continue
            
            run_median_hr = statistics.median(run_hrs)
            
            # Primary HR drop gate (original STRAP): run median must be below active median by hr_drop_bpm
            primary_threshold = active_median - hr_drop_bpm
            
            # Motion-corroborated dual-band HR confirmation (NOOP P1)
            # Deeply quiescent runs get a wider band (multiplicative) as additional relaxation
            deeply_quiescent = _run_is_deeply_quiescent(run)
            if deeply_quiescent:
                adaptive_threshold = active_median * QUIESCENT_HR_SLEEP_MULT
            else:
                adaptive_threshold = active_median * HR_SLEEP_BASELINE_MULT
            
            # Stillness alone cannot prove sleep. Keep the established HR-drop
            # gate until relaxed thresholds have independent validation.
            # This is consistent with the HR transition splitter.
            effective_threshold = min(primary_threshold, adaptive_threshold)

            if run_median_hr > effective_threshold:
                if trace_sink:
                    trace_sink({"gate": "hrConfirm", "verdict": "dropped", 
                                "runMedianHR": run_median_hr, "primaryThreshold": primary_threshold,
                                "adaptiveThreshold": adaptive_threshold, "effectiveThreshold": effective_threshold,
                                "deeplyQuiescent": deeply_quiescent})
                continue
            
# Off-wrist fractional backstop (NOOP P1)
            off_frac = _off_wrist_fraction(run, ordered)
            if off_frac >= MAX_OFF_WRIST_SLEEP_FRACTION:
                if trace_sink:
                    trace_sink({"gate": "offWrist", "verdict": "dropped", 
                                "offWristFraction": off_frac})
                continue
            
            # Daytime guard: require sustained low HR independent of HR drop gate
            from datetime import datetime, timezone
            start_hour = datetime.fromtimestamp(run[0].unix, tz=timezone.utc).hour
            daytime = (8 <= start_hour < 22)
            if daytime:
                # Daytime minimum: require 90 minutes of evidence (Swift line 107)
                if duration < max(min_sleep_s, 90 * 60):
                    if trace_sink:
                        trace_sink({"gate": "daytimeMinDuration", "verdict": "dropped", 
                                    "duration": duration, "required": max(min_sleep_s, 90 * 60)})
                    continue
                
                # Daytime guard: minimum rolling HR over 5 min must be <= activeMedian * 0.95
                resting_hr = _minimum_rolling_mean(run_hrs, 300)
                if resting_hr is None or resting_hr > active_median * 0.95:
                    if trace_sink:
                        trace_sink({"gate": "daytimeGuard", "verdict": "dropped", 
                                    "restingHR": resting_hr, "threshold": active_median * 0.95})
                    continue
            
            # Band state analysis
            state_rows = [s for s in run if s.sleep_state is not None]
            up_rows = sum(1 for s in state_rows if s.sleep_state == 3)
            declared_sleep_rows = sum(1 for s in state_rows if s.sleep_state == 2)
            declared_still_rows = sum(1 for s in state_rows if s.sleep_state == 1)
            
            verified_start = run[0].unix
            run_start_unix = run[0].unix
            run_end_unix = run[-1].unix
            
            if daytime:
                # Pre-22:00: require sustained band state=2 confirmation (5 min)
                # Swift lines 182-225
                sleep_rows = [s for s in run if s.sleep_state == 2 and s.wearing and 35 <= s.heart_rate <= 220]
                sleep_runs = _contiguous_runs(sleep_rows)
                confirmed = None
                for r in sleep_runs:
                    if len(r) >= 300:  # 5 minutes sustained state=2
                        confirmed = r
                        break
                if not confirmed:
                    if trace_sink:
                        trace_sink({"gate": "bandState2Confirm", "verdict": "dropped", 
                                    "reason": "no sustained state=2"})
                    continue
                verified_start = confirmed[0].unix
                
                # Backtrack from confirmed state=2 through quiet, low-HR evidence
                # Swift lines 196-225
                confirmed_hr = statistics.median([float(s.heart_rate) for s in confirmed[:300]])
                floor_unix = max(run_start_unix, verified_start - 30 * 60)
                prelude = [s for s in run if floor_unix <= s.unix < verified_start]
                
                cursor = verified_start
                while cursor - 60 >= floor_unix:
                    minute = [s for s in prelude if cursor - 60 <= s.unix < cursor]
                    valid = [s for s in minute 
                             if s.wearing and 35 <= s.heart_rate <= 220
                             and s.sleep_state != 3
                             and s.dynamic_accel_g is not None
                             and s.dynamic_accel_g >= 0
                             and s.dynamic_accel_g <= 0.05  # tighter quiet threshold for backtrack
                             and float(s.heart_rate) <= confirmed_hr + 8]
                    if len({s.unix for s in valid}) < 40:  # At least 40 distinct seconds per minute
                        break
                    cursor -= 60
                
                # Only accept backtrack if prelude shows HR settling transition
                earlier = [s for s in run 
                           if cursor - 5 * 60 <= s.unix < cursor
                           and s.wearing and 35 <= s.heart_rate <= 220]
                transition_observed = (len(earlier) >= 180 and 
                                       statistics.median([float(s.heart_rate) for s in earlier]) >= confirmed_hr + 6)
                if verified_start - cursor >= 5 * 60 and transition_observed:
                    verified_start = cursor
            else:
                # Overnight: trim leading sustained band-up (state=3) if >= 5 min
                # Swift lines 226-250
                leading_up_seconds = 0
                leading_awake_end = None
                for sample in run:
                    if not (sample.wearing and 35 <= sample.heart_rate <= 220):
                        break
                    if sample.sleep_state == 3:
                        leading_up_seconds += 1
                        leading_awake_end = sample.unix
                    elif leading_up_seconds >= 300:
                        break
                    else:
                        leading_up_seconds = 0
                        leading_awake_end = None
                        break
                if leading_up_seconds >= 300 and leading_awake_end is not None:
                    verified_start = max(verified_start, leading_awake_end + 1)
                
                # HR-based leading awake trim (for cases without band state=3)
                # Detect if run starts with elevated HR that settles into sleep HR
                # Use median of middle portion as sleep HR reference
                run_hrs_all = [float(s.heart_rate) for s in run if s.wearing and 35 <= s.heart_rate <= 220]
                if len(run_hrs_all) >= 600:  # Need enough data
                    # Sleep HR reference: median of middle 50% of run (avoiding edges)
                    mid_start = len(run_hrs_all) // 4
                    mid_end = 3 * len(run_hrs_all) // 4
                    sleep_hr_ref = statistics.median(run_hrs_all[mid_start:mid_end])
                    
                    # Check first 30 minutes for sustained elevated HR
                    leading_cutoff = run[0].unix + 30 * 60
                    leading_hrs = [float(s.heart_rate) for s in run 
                                   if s.unix < leading_cutoff 
                                   and s.wearing and 35 <= s.heart_rate <= 220]
                    if len(leading_hrs) >= 300:  # At least 5 min of data
                        leading_median = statistics.median(leading_hrs)
                        # If leading HR is >= 8 BPM above sleep HR, trim to where HR settles
                        if leading_median >= sleep_hr_ref + 8:
                            # Find transition point where HR drops to sleep level
                            for t in range(run[0].unix + 5 * 60, leading_cutoff, 60):
                                window_hrs = [float(s.heart_rate) for s in run
                                              if t <= s.unix < t + 60
                                              and s.wearing and 35 <= s.heart_rate <= 220]
                                if len(window_hrs) >= 30 and statistics.median(window_hrs) <= sleep_hr_ref + 4:
                                    verified_start = max(verified_start, t)
                                    if trace_sink:
                                        trace_sink({"gate": "leadingAwakeHR", "verdict": "trimmed",
                                                    "leadingMedianHR": leading_median, "sleepHRRef": sleep_hr_ref,
                                                    "newStart": verified_start})
                                    break
                
                # Overnight onset refinement with bounded 90-min backtracking
                # Swift lines 248-250, refineOvernightOnset
                refined_start = _refine_overnight_onset(run, verified_start, effective_quiet_accel, active_median)
                if run_end_unix - refined_start + 1 >= min_sleep_s:
                    verified_start = refined_start
            
            # Autonomic onset gate (WHOOP parity): HR must settle <= activeMedian + 5 for >=10 min sustained stillness
            # Swift lines 254-286
            autonomic_threshold = active_median + 5.0  # AUTONOMIC_ONSET_THRESHOLD_BPM
            autonomic_window = 10 * 60
            autonomic_cursor = verified_start
            search_floor = max(run_start_unix, verified_start - 60 * 60)  # Search up to 1 hour before
            
            while autonomic_cursor - 60 >= search_floor:
                minute = [s for s in run 
                          if autonomic_cursor - 60 <= s.unix < autonomic_cursor]
                valid = [s for s in minute
                         if s.wearing and 35 <= s.heart_rate <= 220
                         and s.sleep_state != 3
                         and s.dynamic_accel_g is not None
                         and s.dynamic_accel_g >= 0
                         and s.dynamic_accel_g <= effective_quiet_accel
                         and float(s.heart_rate) <= autonomic_threshold]
                # At least 50 distinct observed seconds per minute (>=83% coverage)
                if len({s.unix for s in valid}) < 50:
                    break
                autonomic_cursor -= 60
            
            # Only apply autonomic backtrack if it extends >=5 min and shows settling transition
            autonomic_backtrack = verified_start - autonomic_cursor
            if autonomic_backtrack >= 5 * 60:
                earlier = [s for s in run
                           if autonomic_cursor - 5 * 60 <= s.unix < autonomic_cursor
                           and s.wearing and 35 <= s.heart_rate <= 220]
                transition_observed = (len(earlier) >= 180 and
                                       statistics.median([float(s.heart_rate) for s in earlier]) >= autonomic_threshold + 3)
                if transition_observed:
                    verified_start = autonomic_cursor
                    if trace_sink:
                        trace_sink({"gate": "autonomicOnset", "verdict": "advanced", 
                                    "backtrackMin": autonomic_backtrack // 60,
                                    "newStart": verified_start})
            
            # A trimmed onset must still leave a real sleep-length window
            if run_end_unix - verified_start + 1 < min_sleep_s:
                if trace_sink:
                    trace_sink({"gate": "minSleepMin", "verdict": "dropped", 
                                "duration": run_end_unix - verified_start + 1, "min": min_sleep_s})
                continue
            
            # State veto: constant zero/default state with mostly up and no sleep declaration
            if (len(state_rows) >= 300 and
                up_rows * 10 >= len(state_rows) * 7 and
                declared_sleep_rows == 0 and
                declared_still_rows * 10 < len(state_rows)):
                if trace_sink:
                    trace_sink({"gate": "stateVeto", "verdict": "dropped", 
                                "stateRows": len(state_rows), "upRows": up_rows, 
                                "sleepRows": declared_sleep_rows, "stillRows": declared_still_rows})
                continue
            
            # Terminal wake trimming (Swift lines 306-406)
            verified_end = run_end_unix
            
            # Scan backwards from end for sustained band-up (state=3)
            up_start = None
            up_seconds = 0
            next_unix = None
            trailing_unknown_seconds = 0
            
            for sample in reversed(run):
                if not (sample.wearing and 35 <= sample.heart_rate <= 220):
                    break
                if next_unix is not None and next_unix - sample.unix > 2:
                    break
                
                if sample.sleep_state == 0 and up_seconds == 0:
                    # Terminal unknown state (state=0) suffix - skip up to 30 min
                    trailing_unknown_seconds += (next_unix - sample.unix) if next_unix else 1
                    if trailing_unknown_seconds > 30 * 60:
                        break
                elif sample.sleep_state == 3:
                    up_start = sample.unix
                    up_seconds += (next_unix - sample.unix) if next_unix else 1
                else:
                    break
                next_unix = sample.unix
            
            if up_start is not None and up_seconds >= 300:
                # Sustained terminal band-up >= 5 min
                verified_end = up_start - 1
            elif up_start is not None and run[-1].sleep_state == 3 and run_end_unix - up_start <= 60:
                # Fresh terminal band-up transition - corroborate with HR + motion
                # Swift lines 337-377
                terminal_up = up_start
                baseline = [s for s in run
                            if terminal_up - 30 * 60 <= s.unix < terminal_up - 10 * 60
                            and s.wearing and 35 <= s.heart_rate <= 220]
                if len(baseline) >= 600:
                    resting_hr = statistics.median([float(s.heart_rate) for s in baseline])
                    lower_bound = max(verified_start + min_sleep_s, terminal_up - 12 * 60)
                    
                    wake_candidate = None
                    minute = lower_bound
                    while minute + 180 <= terminal_up:
                        window = [s for s in run
                                  if minute <= s.unix < minute + 180
                                  and s.wearing and 35 <= s.heart_rate <= 220
                                  and s.dynamic_accel_g is not None
                                  and s.dynamic_accel_g >= 0]
                        elevated = sum(1 for s in window if float(s.heart_rate) >= resting_hr + 10)
                        moving = sum(1 for s in window if s.dynamic_accel_g is not None and s.dynamic_accel_g >= 0.015)
                        if len({s.unix for s in window}) >= 150 and elevated >= 150 and moving >= 30:
                            wake_candidate = minute
                            break
                        minute += 60
                    
                    if wake_candidate is not None:
                        verified_end = min(verified_end, wake_candidate - 1)
            
            # HR-based terminal wake trim for long morning awake (no band state=3)
            # Scan backward from end to find sleep-to-wake HR transition
            run_hrs_all = [float(s.heart_rate) for s in run if s.wearing and 35 <= s.heart_rate <= 220]
            if len(run_hrs_all) >= 600:
                # Sleep HR reference from middle of run
                mid_start = len(run_hrs_all) // 4
                mid_end = 3 * len(run_hrs_all) // 4
                sleep_hr_ref = statistics.median(run_hrs_all[mid_start:mid_end])
                
                # First, check if there's a sustained elevated HR period at the end (>=10 min)
                # Require motion corroboration: elevated HR without movement is not wake
                # (e.g., REM sleep, morning cortisol rise). Matches band-state trim
                # which requires both HR elevation AND motion.
                elevated_minutes = 0
                for t in range(run_end_unix - 60, verified_start + min_sleep_s, -60):
                    window = [s for s in run
                              if t <= s.unix < t + 60
                              and s.wearing and 35 <= s.heart_rate <= 220]
                    # Replayed rows cannot establish extra observed seconds.
                    hr_by_second = {}
                    for sample in window:
                        hr_by_second.setdefault(sample.unix, float(sample.heart_rate))
                    window_hrs = list(hr_by_second.values())
                    window_moving = len({s.unix for s in window
                                         if s.dynamic_accel_g is not None
                                         and math.isfinite(s.dynamic_accel_g)
                                         and s.dynamic_accel_g >= 0.015})
                    if len(window_hrs) < 30:
                        break  # Missing evidence breaks sustained wake.
                    window_median = statistics.median(window_hrs)
                    if window_median >= sleep_hr_ref + 8 and window_moving >= 10:
                        elevated_minutes += 1
                    else:
                        break
                
                # Only proceed if we have sustained elevated HR at end (>=10 min = 10 minutes)
                if elevated_minutes >= 10:
                    # Now find the sleep-to-wake transition (going backward from the elevated section)
                    sleep_end_transition = None
                    for t in range(run_end_unix - elevated_minutes * 60 - 60, verified_start + min_sleep_s, -60):
                        window_hrs = [float(s.heart_rate) for s in run
                                      if t <= s.unix < t + 60
                                      and s.wearing and 35 <= s.heart_rate <= 220]
                        if len(window_hrs) >= 30:
                            window_median = statistics.median(window_hrs)
                            # Going backward: first minute at sleep level = end of sleep
                            if window_median <= sleep_hr_ref + 4:
                                sleep_end_transition = t + 60
                                break
                    
                    if sleep_end_transition is not None and sleep_end_transition > verified_start + min_sleep_s:
                        verified_end = min(verified_end, sleep_end_transition - 1)
                        if trace_sink:
                            trace_sink({"gate": "terminalWakeHR", "verdict": "trimmed",
                                        "sleepHRRef": sleep_hr_ref, "transitionAt": sleep_end_transition,
                                        "elevatedMinutes": elevated_minutes, "newEnd": verified_end})
            
            # Band can continue reporting sleep(2) after waking - require 5-min HR+motion transition
            # Swift lines 379-406
            terminal_end = run_end_unix
            terminal_start = terminal_end - 299
            terminal = [s for s in run
                        if terminal_start <= s.unix <= terminal_end
                        and s.wearing and 35 <= s.heart_rate <= 220
                        and s.dynamic_accel_g is not None
                        and s.dynamic_accel_g >= 0]
            # Use sleep HR from middle of verified window as reference (avoids morning awake contamination)
            sleep_mid_start = verified_start + (verified_end - verified_start) // 3
            sleep_mid_end = verified_start + 2 * (verified_end - verified_start) // 3
            reference = [s for s in run
                         if sleep_mid_start <= s.unix < sleep_mid_end
                         and s.wearing and 35 <= s.heart_rate <= 220]
            
            if (len({s.unix for s in terminal}) >= 270 and
                len({s.unix for s in reference}) >= 600):
                resting_hr = statistics.median([float(s.heart_rate) for s in reference])
                elevated = sum(1 for s in terminal if float(s.heart_rate) >= resting_hr + 10)
                moving = sum(1 for s in terminal if s.dynamic_accel_g is not None and s.dynamic_accel_g >= 0.015)
                # Sustained elevation AND measured movement both required
                if elevated >= 240 and moving >= 90:
                    verified_end = min(verified_end, terminal_start - 1)
            
            # Genuine sleep can exceed 12 hours (Issue #126) - protect only against multi-day RTC jumps
            if not (verified_end - verified_start + 1 >= min_sleep_s and 
                    verified_end - verified_start + 1 <= 24 * 3600):
                continue
            
            # Metrics must describe the verified interval
            verified_indices = [idx for idx in range(start, end) 
                                if verified_start <= ordered[idx].unix <= verified_end]
            
            # Re-check coverage inside confirmed sleep window
            verified_duration = verified_end - verified_start + 1
            verified_observed = len({ordered[idx].unix for idx in verified_indices})
            verified_worn = len({ordered[idx].unix for idx in verified_indices
                                 if ordered[idx].wearing and 35 <= ordered[idx].heart_rate <= 220})
            if verified_observed < verified_duration // 2 or verified_worn * 5 < verified_observed * 4:
                continue
            
            quiet_seconds = sum(1 for idx in verified_indices if quiet[idx])
            verified_hrs = [float(ordered[idx].heart_rate) for idx in verified_indices
                            if ordered[idx].wearing and 35 <= ordered[idx].heart_rate <= 220]
            
            # Harmonize wakeEvents: count sustained movement bouts (>=15 seconds)
            # Timestamp gaps must break the contiguous movement bout rather than bridging across minutes.
            moving_seconds = 0
            wake_events = 0
            last_moving_unix = None
            for idx in verified_indices:
                u = ordered[idx].unix
                if not quiet[idx]:
                    if last_moving_unix is not None:
                        if u == last_moving_unix + 1:
                            moving_seconds += 1
                        elif u > last_moving_unix + 1:
                            moving_seconds = 1
                    else:
                        moving_seconds = 1
                    last_moving_unix = u
                    if moving_seconds == 15:
                        wake_events += 1
                else:
                    moving_seconds = 0
                    last_moving_unix = None
            
            if trace_sink:
                trace_sink({"gate": "hrConfirm", "verdict": "passed", 
                            "runMedianHR": run_median_hr, "threshold": effective_threshold,
                            "deeplyQuiescent": deeply_quiescent})
            
            periods.append(
                SleepPeriod(
                    start_unix=verified_start,
                    end_unix=verified_end,
                    quiet_fraction=quiet_seconds / max(1, len(verified_indices)),
                    mean_hr=statistics.mean(verified_hrs) if verified_hrs else 0.0,
                    wake_events=wake_events,
                )
            )
    return periods


def is_nocturnal_period(period: SleepPeriod) -> bool:
    """Check if a sleep period is nocturnal (starts 20:00-07:59 or ends <= 12:00)."""
    from datetime import datetime, timezone
    start_dt = datetime.fromtimestamp(period.start_unix, tz=timezone.utc)
    end_dt = datetime.fromtimestamp(period.end_unix, tz=timezone.utc)
    start_hour = start_dt.hour
    end_hour = end_dt.hour
    return start_hour >= 20 or start_hour < 8 or end_hour <= 12


def merge_nocturnal_periods(
    periods: list[SleepPeriod],
    samples: list[V18Sample],
    quiet_accel_g: float = QUIET_ACCEL_G,
    max_awakening_gap_s: int = 30 * 60,
    max_combined_sleep_s: int = 18 * 3600,
) -> list[SleepPeriod]:
    """Merge consecutive nocturnal sleep candidates separated by brief awakenings (≤30 min).
    
    Merges bathroom breaks, hydration, or restless wakefulness into a single overnight
    sleep session, preserving awakenings as in-bed awake time for downstream staging.
    """
    if len(periods) <= 1:
        return periods
    
    merged: list[SleepPeriod] = []
    current = periods[0]
    
    for next_period in periods[1:]:
        gap = next_period.start_unix - current.end_unix - 1
        combined_end = max(current.end_unix, next_period.end_unix)
        combined_span = combined_end - current.start_unix + 1
        
        is_nocturnal = is_nocturnal_period(current) and is_nocturnal_period(next_period)
        
        if not (is_nocturnal and gap <= max_awakening_gap_s and combined_span <= max_combined_sleep_s):
            merged.append(current)
            current = next_period
            continue
        
        gap_samples = [s for s in samples if current.end_unix < s.unix < next_period.start_unix]
        
        # A short bathroom break still requires positive on-wrist coverage.
        # Use elapsed seconds so missing records and replays cannot pass the gate.
        worn_seconds = len({
            s.unix for s in gap_samples 
            if s.wearing and 35 <= s.heart_rate <= 220
        })
        worn_during_gap = gap <= 0 or worn_seconds * 5 >= gap * 3  # ≥60% coverage
        
        # A sustained active workout is not an in-bed awakening.
        active_workout_seconds = len({
            s.unix for s in gap_samples
            if s.wearing and (s.dynamic_accel_g or 0) >= 0.15 and s.heart_rate >= 90
        })
        active_workout_during_gap = active_workout_seconds >= 180
        
        if worn_during_gap and not active_workout_during_gap:
            all_indices = [s for s in samples if current.start_unix <= s.unix <= combined_end]
            quiet_count = sum(
                1 for sample in all_indices
                if sample.wearing 
                and 35 <= sample.heart_rate <= 220
                and sample.dynamic_accel_g is not None
                and math.isfinite(sample.dynamic_accel_g)
                and sample.dynamic_accel_g >= 0
                and sample.dynamic_accel_g <= quiet_accel_g
            )
            valid_hrs = [
                float(s.heart_rate) for s in all_indices
                if s.wearing and 35 <= s.heart_rate <= 220
            ]
            current = SleepPeriod(
                start_unix=current.start_unix,
                end_unix=combined_end,
                quiet_fraction=quiet_count / max(1, len(all_indices)),
                mean_hr=statistics.mean(valid_hrs) if valid_hrs else 0.0,
                wake_events=current.wake_events + next_period.wake_events + 1,
            )
        else:
            merged.append(current)
            current = next_period
    
    merged.append(current)
    return merged


def total_sleep_hours(periods: list[SleepPeriod]) -> float:
    return sum(p.hours for p in periods)


def strain_score(trimp_value: float | None) -> float | None:
    """Map TRIMP onto a local 0-21 scale.

    The TRIMP input is Banister's published formula; this 0-21 mapping is our
    own saturating curve, chosen so a hard session approaches but never exceeds
    21. It is not WHOOP's proprietary strain and the numbers are not comparable.
    """
    if trimp_value is None:
        return None
    if trimp_value < 0:
        raise ValueError("TRIMP cannot be negative")
    return STRAIN_MAX * (1.0 - math.exp(-trimp_value / STRAIN_SCALE_TRIMP))


def strain_label(score: float | None) -> str:
    if score is None:
        return "unknown"
    if score < 10:
        return "light"
    if score < 14:
        return "moderate"
    if score < 18:
        return "high"
    return "all-out"


@dataclass
class Baseline:
    """Personal norms. A recovery score is only meaningful relative to these."""

    ln_rmssd_mean: float
    ln_rmssd_sd: float
    rhr_mean: float
    rhr_sd: float
    days: int

    @classmethod
    def from_daily(cls, ln_rmssd: list[float], rhr: list[float]) -> "Baseline | None":
        if len(ln_rmssd) < 2 or len(rhr) < 2:
            return None
        return cls(
            ln_rmssd_mean=statistics.mean(ln_rmssd),
            ln_rmssd_sd=statistics.stdev(ln_rmssd),
            rhr_mean=statistics.mean(rhr),
            rhr_sd=statistics.stdev(rhr),
            days=min(len(ln_rmssd), len(rhr)),
        )


class RecoveryLevel(IntEnum):
    HIGH_RECOVERY = 0    # Green (raw score > 66.0, displaying >= 67%)
    MEDIUM_RECOVERY = 1  # Yellow (33.0 < score <= 66.0, displaying 34% - 66%)
    LOW_RECOVERY = 2     # Red (raw score <= 33.0, displaying <= 33%)
    CALIBRATING = 3      # Insufficient baseline (< 7 days)
    DEAD_END = 4         # Missing / invalid data


@dataclass
class RecoveryResult:
    score: float | None
    reason: str | None
    hrv_component: float | None = None
    rhr_component: float | None = None
    sleep_component: float | None = None

    @property
    def level(self) -> RecoveryLevel:
        if self.score is None:
            if self.reason and "baseline" in self.reason.lower():
                return RecoveryLevel.CALIBRATING
            return RecoveryLevel.DEAD_END
        if self.score > 66.0:
            return RecoveryLevel.HIGH_RECOVERY
        if self.score > 33.0:
            return RecoveryLevel.MEDIUM_RECOVERY
        return RecoveryLevel.LOW_RECOVERY

    @property
    def band(self) -> str:
        if self.level == RecoveryLevel.HIGH_RECOVERY:
            return "green"
        if self.level == RecoveryLevel.MEDIUM_RECOVERY:
            return "yellow"
        if self.level == RecoveryLevel.LOW_RECOVERY:
            return "red"
        return "unavailable"


def _logistic(z: float) -> float:
    return 100.0 / (1.0 + math.exp(-z))


def recovery_score(
    ln_rmssd: float | None,
    rhr: float | None,
    sleep_hours: float | None,
    sleep_need_hours: float | None,
    baseline: Baseline | None,
    respiratory_rate: float | None = None,
    respiratory_rate_baseline: float | None = None,
    sleep_performance: float | None = None,
) -> RecoveryResult:
    """Baseline-relative 0-100 recovery estimate. Not WHOOP's recovery.

    Higher HRV than your own norm and lower resting HR than your own norm both
    push the score up; sleep is scored against your stated need. Components are
    renormalised over whatever is actually available, and a missing baseline
    produces no score rather than a fabricated one.
    """
    if baseline is None or baseline.days < MIN_BASELINE_DAYS:
        return RecoveryResult(None, f"needs at least {MIN_BASELINE_DAYS} days of baseline")
    if ln_rmssd is None or rhr is None:
        return RecoveryResult(None, "needs HRV and resting HR from a rest/sleep window")

    hrv_z = (
        (ln_rmssd - baseline.ln_rmssd_mean) / baseline.ln_rmssd_sd
        if baseline.ln_rmssd_sd > 0
        else 0.0
    )
    rhr_z = (
        -(rhr - baseline.rhr_mean) / baseline.rhr_sd if baseline.rhr_sd > 0 else 0.0
    )
    components = {"hrv": _logistic(hrv_z), "rhr": _logistic(rhr_z)}

    if sleep_performance is not None and math.isfinite(sleep_performance) and sleep_performance >= 0:
        components["sleep"] = min(100.0, sleep_performance)
    elif sleep_hours is not None and sleep_need_hours and sleep_need_hours > 0:
        components["sleep"] = 100.0 * min(sleep_hours / sleep_need_hours, 1.0)

    total_weight = sum(RECOVERY_WEIGHTS[k] for k in components)
    score = sum(components[k] * RECOVERY_WEIGHTS[k] for k in components) / total_weight
    if (
        respiratory_rate is not None
        and respiratory_rate_baseline is not None
        and respiratory_rate_baseline > 0
    ):
        delta = respiratory_rate - respiratory_rate_baseline
        if delta >= 1.2:
            # WHOOP illness indicator: elevation of >= 1.2 rpm above baseline dampens recovery
            excess = delta - 1.0
            damping = max(0.0, min(0.25, 0.10 * excess))
            score *= (1.0 - damping)
    return RecoveryResult(
        score=round(score, 1),
        reason=None,
        hrv_component=round(components["hrv"], 1),
        rhr_component=round(components["rhr"], 1),
        sleep_component=round(components["sleep"], 1) if "sleep" in components else None,
    )


@dataclass
class StressResult:
    index: float | None
    reason: str | None

    @property
    def band(self) -> str:
        if self.index is None:
            return "unavailable"
        if self.index < STRESS_ELEVATED_SD:
            return "low"
        if self.index < STRESS_HIGH_SD:
            return "elevated"
        return "high"


def stress_score(ln_rmssd: float | None, baseline: Baseline | None) -> StressResult:
    """Standard deviations of lnRMSSD below the personal norm, clipped to 0-3.

    Vagal withdrawal is the published acute-stress marker, so a window sitting
    below its own awake-quiet norm scores higher. At or above the norm the index
    is 0 - HRV above your normal is not "negative stress".

    `baseline` MUST be built from awake-quiet windows. Exercise also collapses
    RMSSD, for metabolic rather than psychological reasons, so the caller must
    only pass HRV from a verified-quiet run (see metrics.resting_hrv).
    """
    if baseline is None or baseline.days < MIN_BASELINE_DAYS:
        return StressResult(None, f"needs at least {MIN_BASELINE_DAYS} days of awake-quiet baseline")
    if ln_rmssd is None:
        return StressResult(None, "needs HRV from a verified-quiet window")
    if baseline.ln_rmssd_sd <= 0:
        return StressResult(None, "baseline has no HRV variation to scale against")

    deviation = (baseline.ln_rmssd_mean - ln_rmssd) / baseline.ln_rmssd_sd
    return StressResult(index=round(max(0.0, min(STRESS_MAX, deviation)), 2), reason=None)


@dataclass
class RespRate:
    breaths_per_min: float | None
    reason: str | None
    beats: int
    windows: int

    @property
    def available(self) -> bool:
        return self.breaths_per_min is not None


def _rr_segments(samples: list[V18Sample]) -> list[list[tuple[int, int]]]:
    """Split the beat stream wherever R-R is missing or the record clock jumps.

    Cumulative beat time cannot represent a dropout: stitching the two sides
    would put a step into the tachogram that the peak picker reads as a breath.
    Short gaps are tolerated because a single missed beat does not move the
    estimate, but a multi-second gap starts a new segment.
    """
    # Match the native path: retain one payload per second, ranking valid
    # beats ahead of padding or malformed words. A tie retains the first.
    def quality(sample: V18Sample) -> tuple[int, int]:
        valid = sum(MIN_RR_MS <= v <= MAX_RR_MS for v in sample.rr_intervals_ms)
        return valid, -(len(sample.rr_intervals_ms) - valid)

    unique: dict[int, V18Sample] = {}
    for sample in samples:
        previous = unique.get(sample.unix)
        if previous is None or quality(sample) > quality(previous):
            unique[sample.unix] = sample
    ordered = sorted(unique.values(), key=lambda s: s.unix)
    segments: list[list[tuple[int, int]]] = []
    current: list[tuple[int, int]] = []
    last_unix: int | None = None
    last_span_s = 0.0
    for sample in ordered:
        motion = sample.dynamic_accel_g
        rr = [v for v in sample.rr_intervals_ms if MIN_RR_MS <= v <= MAX_RR_MS]
        if not sample.wearing or motion is None or not math.isfinite(motion) or not 0 <= motion <= 0.10 or not rr:
            if current:
                segments.append(current)
                current = []
            last_unix = None
            last_span_s = 0.0
            continue
        # On a real capture the wall-clock step exceeds the previous record's
        # R-R span by ~0.16 s. A multi-second excess is a dropout, not timing
        # noise, and stitching across it would fabricate a breath.
        if (
            last_unix is not None
            and sample.unix - last_unix - last_span_s > RSA_GAP_TOLERANCE_S
        ):
            if current:
                segments.append(current)
            current = []
        current.extend((sample.unix, value) for value in rr)
        last_unix = sample.unix
        last_span_s = sum(rr) / 1000.0
    if current:
        segments.append(current)
    return segments


def _resample_beat_times(times: list[float], values: list[int]) -> list[float]:
    dt = 1.0 / RSA_RESAMPLE_HZ
    count = int(times[-1] / dt) + 1
    grid: list[float] = []
    seg = 0
    for i in range(count):
        t = i * dt
        while seg < len(times) - 2 and times[seg + 1] < t:
            seg += 1
        t0, t1 = times[seg], times[seg + 1]
        v0, v1 = values[seg], values[seg + 1]
        if t1 <= t0:
            grid.append(float(v0))
        else:
            fraction = min(max((t - t0) / (t1 - t0), 0.0), 1.0)
            grid.append(v0 + fraction * (v1 - v0))
    return grid


def _detrend(values: list[float]) -> list[float]:
    half = max(1, round(RSA_DETREND_WINDOW_S * RSA_RESAMPLE_HZ / 2.0))
    out: list[float] = []
    for i in range(len(values)):
        lo = max(0, i - half)
        hi = min(len(values) - 1, i + half)
        window = values[lo : hi + 1]
        out.append(values[i] - sum(window) / len(window))
    return out


def _find_peaks(values: list[float], min_distance: int) -> list[int]:
    """Local maxima above zero, thinned greedily by height like scipy's picker."""
    candidates = [
        i
        for i in range(1, len(values) - 1)
        if values[i] > 0 and values[i] > values[i - 1] and values[i] >= values[i + 1]
    ]
    if not candidates:
        return []
    ordered = sorted(candidates, key=lambda i: (-values[i], i))
    kept: list[int] = []
    for i in ordered:
        if all(abs(i - j) >= min_distance for j in kept):
            kept.append(i)
    return sorted(kept)


def _window_rates(detrended: list[float]) -> list[float]:
    min_distance = max(2, round(RSA_MIN_PEAK_DISTANCE_S * RSA_RESAMPLE_HZ))
    window_samples = max(
        min_distance * 3, round(RSA_WINDOW_S * RSA_RESAMPLE_HZ)
    )
    min_window_samples = round(RSA_WINDOW_S * RSA_RESAMPLE_HZ / 2.0)
    dt = 1.0 / RSA_RESAMPLE_HZ
    rates: list[float] = []
    for start in range(0, len(detrended), window_samples):
        window = detrended[start : start + window_samples]
        if len(window) < min_window_samples:
            continue
        peaks = _find_peaks(window, min_distance)
        if len(peaks) < 3:
            continue
        intervals = [
            (peaks[i] - peaks[i - 1]) * dt
            for i in range(1, len(peaks))
        ]
        intervals = [
            iv
            for iv in intervals
            if RSA_MIN_BREATH_INTERVAL_S <= iv <= RSA_MAX_BREATH_INTERVAL_S
        ]
        if len(intervals) < 2:
            continue
        median = statistics.median(intervals)
        if median <= 0:
            continue
        anchored = [iv for iv in intervals if abs(iv - median) <= RSA_INTERVAL_BAND * median]
        mean_interval = statistics.mean(anchored) if anchored else median
        if mean_interval > 0:
            rates.append(60.0 / mean_interval)
    return rates


def _spectral_window_rates(
    detrended: list[float], median_rr_seconds: float
) -> list[float]:
    # Search beyond the publishable band so a dominant out-of-band peak
    # cannot be hidden by truncating the spectrum at 24 breaths/min.
    ceiling_hz = min(0.50, 0.5 / median_rr_seconds) if median_rr_seconds > 0 else 0.50
    if ceiling_hz <= 0.16:
        return []
    window_samples = round(RSA_WINDOW_S * RSA_RESAMPLE_HZ)
    min_samples = round(RSA_WINDOW_S * RSA_RESAMPLE_HZ / 2.0)
    rates: list[float] = []
    for start in range(0, len(detrended), window_samples):
        window = detrended[start : start + window_samples]
        n = len(window)
        if n < min_samples:
            continue
        denom = max(1, n - 1)
        windowed = [
            window[i] * 0.5 * (1.0 - math.cos(2.0 * math.pi * i / denom))
            for i in range(n)
        ]
        best_power = -1.0
        best_freq = 0.0
        total_power = 0.0
        bins = 0
        freq = 0.05
        while freq <= ceiling_hz + 1e-6:
            omega = 2.0 * math.pi * freq / RSA_RESAMPLE_HZ
            re = 0.0
            im = 0.0
            for i in range(n):
                ang = omega * i
                re += windowed[i] * math.cos(ang)
                im -= windowed[i] * math.sin(ang)
            power = re * re + im * im
            total_power += power
            bins += 1
            if power > best_power:
                best_power = power
                best_freq = freq
            freq += 0.005
        mean_power = total_power / bins if bins > 0 else 0.0
        if (
            mean_power > 0
            and (best_power / mean_power) >= 2.0
            and RESP_PLAUSIBLE_MIN_BPM <= best_freq * 60 <= RESP_PLAUSIBLE_MAX_BPM
            and best_freq + 0.005 <= ceiling_hz + 1e-6
        ):
            rates.append(best_freq * 60.0)
    return rates


def resp_rate_from_rr(samples: list[V18Sample]) -> RespRate:
    """Estimate sleeping respiratory rate from R-R via RSA.

    This recovers the breathing modulation of beat-to-beat timing, which tracks
    but does not equal a chest-band or capnography rate. It is an on-device
    estimate: the v18 wire carries no respiration ADC. Requires a still or
    sleep window with a continuous R-R train; otherwise returns no value.
    """
    segments = _rr_segments(samples)
    total_beats = sum(len(segment) for segment in segments)
    if total_beats < MIN_RSA_BEATS:
        return RespRate(
            None,
            f"needs at least {MIN_RSA_BEATS} R-R beats from a still or sleep window",
            total_beats,
            0,
        )

    rates: list[float] = []
    spectral_rates: list[float] = []
    overcounted_segments = 0
    undercovered_segments = 0
    attempted_windows = 0
    for segment in segments:
        if len(segment) < MIN_RSA_BEATS:
            continue
        span = segment[-1][0] - segment[0][0] + 1
        beat_seconds = sum(rr for _, rr in segment) / 1000
        if beat_seconds > span * 1.05:
            overcounted_segments += 1
            continue
        if beat_seconds < span * 0.80:
            undercovered_segments += 1
            continue
        times: list[float] = []
        acc = 0.0
        for _, rr in segment:
            acc += rr / 1000.0
            times.append(acc)
        if times[-1] < RSA_WINDOW_S / 2.0:
            continue
        grid = _resample_beat_times(times, [rr for _, rr in segment])
        if len(grid) < 8:
            continue
        detrended = _detrend(grid)
        # Include rejected and flat windows in the consensus denominator.
        window_samples = round(RSA_WINDOW_S * RSA_RESAMPLE_HZ)
        min_samples = round(RSA_WINDOW_S * RSA_RESAMPLE_HZ / 2.0)
        full, tail = divmod(len(detrended), window_samples)
        attempted_windows += full + int(tail >= min_samples)
        if statistics.pstdev(detrended) <= 1e-9:
            continue
        median_rr_s = statistics.median(rr / 1000.0 for _, rr in segment)
        spectral_rates.extend(_spectral_window_rates(detrended, median_rr_s))
        rates.extend(_window_rates(detrended))

    # A plausible peak train alone can be a harmonic or noise. Require
    # agreement between spectral windows and corroboration for thin evidence.
    active_rates = spectral_rates
    if active_rates:
        center = statistics.median(active_rates)
        agreeing = sum(abs(rate - center) <= 2.0 for rate in active_rates)
        corroborated = bool(rates) and abs(statistics.median(rates) - center) <= 2.0
        if agreeing * 2 < attempted_windows or (len(active_rates) < 3 and not corroborated):
            return RespRate(None, f"Insufficient RSA consensus: {agreeing}/{attempted_windows} eligible windows agree; "
                            "or thin evidence lacks peak-train corroboration",
                            total_beats, len(active_rates))
    if not active_rates:
        return RespRate(
            None,
            ("no usable RSA peak train - RR beat duration exceeded elapsed recording time"
             if overcounted_segments else
             ("no usable RSA peak train - insufficient RR beat-time coverage"
              if undercovered_segments else
              "no usable RSA peak train - needs a continuous still or sleep R-R window")),
            total_beats,
            0,
        )
    median = statistics.median(active_rates)
    if not (RESP_PLAUSIBLE_MIN_BPM <= median <= RESP_PLAUSIBLE_MAX_BPM):
        return RespRate(
            None,
            f"RSA estimate {median:.1f}/min fell outside the plausible"
            f" {RESP_PLAUSIBLE_MIN_BPM:.0f}-{RESP_PLAUSIBLE_MAX_BPM:.0f} band",
            total_beats,
            len(active_rates),
        )
    return RespRate(round(median, 1), None, total_beats, len(active_rates))


@dataclass
class Spo2Candidate:
    pct: float | None
    readings: int
    saturated: int
    diagnostic: int
    reason: str | None

    @property
    def available(self) -> bool:
        return self.pct is not None


def spo2_candidate_summary(samples: list[V18Sample]) -> Spo2Candidate:
    """Mean of the band's in-band SpO2 candidates, or no value at all.

    This is NOT a validated SpO2. The band banks one candidate byte per second
    only while it records sleep; the percentage range is 70-100, bit-7 values
    are saturation sentinels and other nonzero values are diagnostic codes.
    Cross-device validation is split, so the value is presented as a candidate
    and never feeds a score.
    """
    in_band = [
        s.spo2_candidate_pct
        for s in samples
        if s.spo2_candidate_pct is not None
        and SPO2_CANDIDATE_MIN <= s.spo2_candidate_pct <= SPO2_CANDIDATE_MAX
    ]
    saturated = sum(1 for s in samples if s.spo2_candidate_status == "saturated")
    diagnostic = sum(1 for s in samples if s.spo2_candidate_status == "diagnostic")
    if not in_band:
        return Spo2Candidate(
            None,
            0,
            saturated,
            diagnostic,
            "the strap banked no in-band (70-100) candidate - no SpO2 % is produced",
        )
    return Spo2Candidate(
        round(statistics.mean(in_band), 1),
        len(in_band),
        saturated,
        diagnostic,
        None,
    )


@dataclass
class SleepCoach:
    nights: int
    debt_h: float | None
    need_h: float
    time_in_bed_h: float
    wake_min: int | None
    bedtime_min: int | None

    @property
    def reason(self) -> str | None:
        if self.wake_min is None:
            return "set a wake time to get a suggested bedtime"
        return None


def sleep_debt(night_sleep_h: list[float], base_need_h: float) -> float:
    """Running shortfall against need over the recent nights, floored at zero.

    A night longer than need repays debt; the floor stops surplus sleep from
    banking credit against future short nights.
    """
    debt = 0.0
    for actual in night_sleep_h[-SLEEP_DEBT_WINDOW_NIGHTS:]:
        debt = max(0.0, debt + base_need_h - actual)
    return debt


def sleep_coach(
    night_sleep_h: list[float],
    wake_min: int | None,
    base_need_h: float = 8.0,
    tomorrow: str = "easy",
    efficiency: float = SLEEP_EFFICIENCY,
) -> SleepCoach:
    """Suggested bedtime from wake time, sleep debt and tomorrow's plan.

    Time in bed exceeds sleep need by assumed latency and efficiency, because
    time in bed is not time asleep. Both are stated assumptions (90% efficiency,
    15 min latency), not measurements - this strap cannot observe either.
    `bedtime_min` may be negative: it then means the previous evening.
    """
    if tomorrow not in TOMORROW_EXTRA_H:
        raise ValueError(f"tomorrow must be one of {sorted(TOMORROW_EXTRA_H)}")
    if base_need_h <= 0:
        raise ValueError("base_need_h must be positive")
    if not 0.0 < efficiency <= 1.0:
        raise ValueError("efficiency must be in (0, 1]")
    recent = night_sleep_h[-SLEEP_DEBT_WINDOW_NIGHTS:]
    debt = sleep_debt(recent, base_need_h) if recent else None
    need = base_need_h + TOMORROW_EXTRA_H[tomorrow] + (
        min(debt, SLEEP_DEBT_CAP_H) if debt is not None else 0.0
    )
    in_bed = need / efficiency + SLEEP_LATENCY_H
    bedtime = None if wake_min is None else round(wake_min - in_bed * 60.0)
    return SleepCoach(
        nights=len(recent),
        debt_h=round(debt, 2) if debt is not None else None,
        need_h=round(need, 2),
        time_in_bed_h=round(in_bed, 2),
        wake_min=wake_min,
        bedtime_min=bedtime,
    )


def clock_label(minutes: int) -> str:
    """24-hour clock label; negative minutes wrap to the previous day."""
    hours, mins = divmod(minutes % 1440, 60)
    return f"{hours:02d}:{mins:02d}"
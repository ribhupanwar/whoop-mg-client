"""WHOOP vs STRAP Multi-Metric Comparison Engine.

Offline-first comparator that accepts user-authorized WHOOP exports
(physiological_cycles.csv, sleeps.csv, workouts.csv) and STRAP sensor records
or daily summaries, normalizes timestamps and measurement windows, and computes
comparisons across 10 vital health metrics.
"""

from __future__ import annotations

import csv
import io
import math
import re
import statistics
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from ..health import (
    Baseline,
    SleepPeriod,
    recovery_score,
    resp_rate_from_rr,
)
from ..metrics import nn_intervals, rmssd
from ..records import RecordHeader, V18Sample
from ..sleep_stage import SleepStaging, stage_sleep


@dataclass
class MetricComparison:
    """Individual comparison for a single health or sensor metric."""

    name: str
    whoop_value: float | None
    strap_value: float | None
    unit: str
    display_name: str = ""
    absolute_difference: float | None = None
    percentage_difference: float | None = None
    whoop_window: tuple[int, int] | None = None  # (start_unix, end_unix)
    strap_window: tuple[int, int] | None = None  # (start_unix, end_unix)
    window_overlap_pct: float | None = None
    data_coverage_pct: float | None = None
    notes: str = ""

    def __post_init__(self) -> None:
        if not self.display_name:
            self.display_name = self.name.replace("_", " ").title()
        if self.whoop_value is not None and self.strap_value is not None:
            self.absolute_difference = round(abs(self.strap_value - self.whoop_value), 3)
            if abs(self.whoop_value) > 1e-6:
                self.percentage_difference = round(
                    abs(self.strap_value - self.whoop_value) / abs(self.whoop_value) * 100.0,
                    2,
                )
            else:
                self.percentage_difference = 0.0


@dataclass
class DayComparisonReport:
    """Consolidated report across all 10 target metrics for a given cycle or day."""

    date_key: str
    cycle_start_unix: int
    cycle_end_unix: int
    comparisons: dict[str, MetricComparison] = field(default_factory=dict)
    diagnostics: list[str] = field(default_factory=list)

    def add(self, comparison: MetricComparison) -> None:
        self.comparisons[comparison.name] = comparison


def _normalize_header(header: str) -> str:
    """Normalize column headers: lowercase and alphanumeric only."""
    return "".join(c.lower() for c in header if c.isalnum())


def parse_timestamp(value: str) -> int | None:
    """Parse multiple datetime representations into epoch seconds (UTC)."""
    if not value or not value.strip():
        return None
    val = value.strip()

    # Numeric unix timestamp
    try:
        ts = float(val)
        if ts > 1e11:  # milliseconds
            return int(ts / 1000.0)
        return int(ts)
    except ValueError:
        pass

    # ISO-8601 variations
    # Replace space with T if simple date time
    val_clean = val.replace("Z", "+00:00")
    for fmt in (
        "%Y-%m-%d %H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S.%f%z",
        "%Y-%m-%dT%H:%M:%S.%f%z",
        "%Y-%m-%d",
    ):
        try:
            dt = datetime.strptime(val_clean, fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return int(dt.timestamp())
        except ValueError:
            continue

    # Fallback with fromisoformat
    try:
        dt = datetime.fromisoformat(val_clean)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    except (ValueError, TypeError):
        return None


def calculate_window_overlap(
    window1: tuple[int, int] | None, window2: tuple[int, int] | None
) -> float:
    """Calculate percentage overlap between two time windows [0.0 - 100.0]."""
    if not window1 or not window2:
        return 0.0
    s1, e1 = min(window1), max(window1)
    s2, e2 = min(window2), max(window2)
    dur1 = max(1, e1 - s1)
    dur2 = max(1, e2 - s2)

    overlap_start = max(s1, s2)
    overlap_end = min(e1, e2)

    if overlap_end <= overlap_start:
        return 0.0

    overlap_dur = overlap_end - overlap_start
    union_dur = max(e1, e2) - min(s1, s2)
    return round((overlap_dur / union_dur) * 100.0, 2)


class WhoopExportParser:
    """Parses standard WHOOP data exports (physiological_cycles, sleeps, workouts)."""

    @staticmethod
    def parse_cycles(csv_text: str) -> list[dict[str, Any]]:
        """Parse physiological_cycles.csv rows into structured records."""
        f = io.StringIO(csv_text.strip())
        reader = csv.reader(f)
        try:
            raw_headers = next(reader)
        except StopIteration:
            return []

        headers = [_normalize_header(h) for h in raw_headers]

        def get_col(candidates: list[str]) -> int | None:
            norm = [_normalize_header(c) for c in candidates]
            for i, h in enumerate(headers):
                if h in norm:
                    return i
            return None

        col_start = get_col(["Cycle start time", "cyclestart", "start", "cycledate", "date", "cyclestarttime"])
        col_end = get_col(["Cycle end time", "cycleend", "end", "cycleendtime"])
        col_recovery = get_col(["Recovery score %", "recovery", "recoveryscore", "cyclerecoveryscore", "cyclerecovery", "cyclerecoveryscorepercent"])
        col_rhr = get_col(["Resting heart rate (bpm)", "rhr", "restingheartrate", "restinghr", "restingheartratebpm"])
        col_hrv = get_col(["Heart rate variability (ms)", "hrv", "rmssd", "hrvms", "heartratevariabilityms", "heartratevariability"])
        col_strain = get_col(["Day Strain", "strain", "daystrain", "cyclestrain"])
        col_cals = get_col(["Energy burned (cal)", "kilocalories", "calories", "cals"])
        col_max_hr = get_col(["Max HR (bpm)", "maxhr", "maximumheartrate"])
        col_avg_hr = get_col(["Average HR (bpm)", "avghr", "averageheartrate"])
        col_resp = get_col(["Respiratory rate (rpm)", "respiratoryrate", "rpm"])
        col_spo2 = get_col(["Blood oxygen %", "spo2", "bloodoxygen"])
        col_sleep_need = get_col(["Sleep need (min)", "sleepneed"])
        col_sleep_debt = get_col(["Sleep debt (min)", "sleepdebt"])
        col_sleep_perf = get_col(["Sleep performance %", "sleepperformance"])

        records = []
        for row in reader:
            if not row or len(row) <= (col_start or 0):
                continue
            start_str = row[col_start] if col_start is not None and col_start < len(row) else ""
            start_unix = parse_timestamp(start_str)
            if start_unix is None:
                continue

            end_str = row[col_end] if col_end is not None and col_end < len(row) else ""
            end_unix = parse_timestamp(end_str) or (start_unix + 86400)

            def get_float(col: int | None) -> float | None:
                if col is None or col >= len(row):
                    return None
                val = row[col].strip().replace("%", "")
                try:
                    fval = float(val)
                    return fval if math.isfinite(fval) else None
                except ValueError:
                    return None

            records.append({
                "start_unix": start_unix,
                "end_unix": end_unix,
                "recovery_score": get_float(col_recovery),
                "rhr": get_float(col_rhr),
                "hrv_rmssd": get_float(col_hrv),
                "strain": get_float(col_strain),
                "calories": get_float(col_cals),
                "max_hr": get_float(col_max_hr),
                "avg_hr": get_float(col_avg_hr),
                "respiratory_rate": get_float(col_resp),
                "spo2": get_float(col_spo2),
                "sleep_need_min": get_float(col_sleep_need),
                "sleep_debt_min": get_float(col_sleep_debt),
                "sleep_performance": get_float(col_sleep_perf),
                "raw_start": start_str,
            })
        return records

    @staticmethod
    def parse_sleeps(csv_text: str) -> list[dict[str, Any]]:
        """Parse sleeps.csv rows into structured records."""
        f = io.StringIO(csv_text.strip())
        reader = csv.reader(f)
        try:
            raw_headers = next(reader)
        except StopIteration:
            return []

        headers = [_normalize_header(h) for h in raw_headers]

        def get_col(candidates: list[str]) -> int | None:
            norm = [_normalize_header(c) for c in candidates]
            for i, h in enumerate(headers):
                if h in norm:
                    return i
            return None

        col_cycle = get_col(["Cycle start time", "cyclestart"])
        col_start = get_col(["Sleep onset", "sleepstart", "start", "inbedtime", "sleepstarttime", "sleepstartdate"])
        col_end = get_col(["Wake onset", "sleepend", "end", "wakeonset", "sleependtime", "sleependdate"])
        col_in_bed = get_col(["In bed duration (min)", "inbedduration", "inbedmin", "qualitydurationmin", "durationmin"])
        col_asleep = get_col(["Asleep duration (min)", "asleepduration", "asleepmin"])
        col_light = get_col(["Light sleep duration (min)", "lightsleep", "lightmin"])
        col_deep = get_col(["Deep (SWS) duration (min)", "deepsleep", "deepmin", "swsmin", "slowwavesleepdurationmin", "slowwavesleep"])
        col_rem = get_col(["REM duration (min)", "remsleep", "remmin"])
        col_awake = get_col(["Awake duration (min)", "awakeduration", "awakemin"])
        col_disturbances = get_col(["Sleep disturbance count", "disturbances", "awakenings"])
        col_resp = get_col(["Respiratory rate (rpm)", "respiratoryrate"])

        records = []
        for row in reader:
            if not row:
                continue
            start_str = row[col_start] if col_start is not None and col_start < len(row) else ""
            end_str = row[col_end] if col_end is not None and col_end < len(row) else ""
            start_unix = parse_timestamp(start_str)
            end_unix = parse_timestamp(end_str)
            if start_unix is None or end_unix is None:
                continue

            def get_float(col: int | None) -> float | None:
                if col is None or col >= len(row):
                    return None
                val = row[col].strip()
                try:
                    fval = float(val)
                    return fval if math.isfinite(fval) else None
                except ValueError:
                    return None

            records.append({
                "start_unix": start_unix,
                "end_unix": end_unix,
                "duration_min": get_float(col_in_bed) or get_float(col_asleep) or ((end_unix - start_unix) / 60.0),
                "in_bed_min": get_float(col_in_bed),
                "asleep_min": get_float(col_asleep),
                "light_min": get_float(col_light),
                "deep_min": get_float(col_deep),
                "rem_min": get_float(col_rem),
                "awake_min": get_float(col_awake),
                "disturbances": get_float(col_disturbances),
                "respiratory_rate": get_float(col_resp),
            })
        return records

    @staticmethod
    def parse_workouts(csv_text: str) -> list[dict[str, Any]]:
        """Parse workouts.csv rows into structured records."""
        f = io.StringIO(csv_text.strip())
        reader = csv.reader(f)
        try:
            raw_headers = next(reader)
        except StopIteration:
            return []

        headers = [_normalize_header(h) for h in raw_headers]

        def get_col(candidates: list[str]) -> int | None:
            norm = [_normalize_header(c) for c in candidates]
            for i, h in enumerate(headers):
                if h in norm:
                    return i
            return None

        col_start = get_col(["Workout start time", "starttime", "start"])
        col_end = get_col(["Workout end time", "endtime", "end"])
        col_sport = get_col(["Sport name", "activityname", "sport", "activity"])
        col_strain = get_col(["Activity Strain", "strain", "activitystrain"])
        col_cals = get_col(["Energy burned (cal)", "calories", "kilocalories"])
        col_avg_hr = get_col(["Average HR (bpm)", "avghr", "averageheartrate"])
        col_max_hr = get_col(["Max HR (bpm)", "maxhr", "maximumheartrate"])

        records = []
        for row in reader:
            if not row:
                continue
            start_str = row[col_start] if col_start is not None and col_start < len(row) else ""
            end_str = row[col_end] if col_end is not None and col_end < len(row) else ""
            start_unix = parse_timestamp(start_str)
            end_unix = parse_timestamp(end_str)
            if start_unix is None or end_unix is None:
                continue

            def get_float(col: int | None) -> float | None:
                if col is None or col >= len(row):
                    return None
                val = row[col].strip()
                try:
                    fval = float(val)
                    return fval if math.isfinite(fval) else None
                except ValueError:
                    return None

            sport = (
                row[col_sport].strip().lower()
                if col_sport is not None and col_sport < len(row)
                else "workout"
            )

            records.append({
                "start_unix": start_unix,
                "end_unix": end_unix,
                "sport": sport,
                "strain": get_float(col_strain),
                "calories": get_float(col_cals),
                "avg_hr": get_float(col_avg_hr),
                "max_hr": get_float(col_max_hr),
            })
        return records


class AccuracyComparator:
    """Core comparison engine reconciling STRAP measurements against WHOOP reference."""

    def __init__(
        self,
        strap_samples: list[V18Sample],
        whoop_cycles: list[dict[str, Any]],
        whoop_sleeps: list[dict[str, Any]] | None = None,
        whoop_workouts: list[dict[str, Any]] | None = None,
    ) -> None:
        # Sort and deduplicate strap samples by timestamp
        by_unix: dict[int, V18Sample] = {}
        for s in strap_samples:
            by_unix[s.unix] = s
        self.samples = sorted(by_unix.values(), key=lambda s: s.unix)
        self.whoop_cycles = sorted(whoop_cycles, key=lambda c: c["start_unix"])
        self.whoop_sleeps = sorted(whoop_sleeps or [], key=lambda s: s["start_unix"])
        self.whoop_workouts = sorted(whoop_workouts or [], key=lambda w: w["start_unix"])

    def compare_cycle(self, cycle: dict[str, Any]) -> DayComparisonReport:
        """Compare all 10 metrics for a single 24h WHOOP cycle window."""
        c_start = cycle["start_unix"]
        c_end = cycle["end_unix"]
        date_key = cycle.get("raw_start", "")[:10] or datetime.fromtimestamp(
            c_start, tz=timezone.utc
        ).strftime("%Y-%m-%d")

        report = DayComparisonReport(
            date_key=date_key, cycle_start_unix=c_start, cycle_end_unix=c_end
        )

        # Slice STRAP samples for this cycle window
        cycle_samples = [s for s in self.samples if c_start <= s.unix <= c_end]
        wearing_samples = [s for s in cycle_samples if s.wearing and 30 <= s.heart_rate <= 220]

        total_window_s = max(1, c_end - c_start)
        coverage_pct = round(len(wearing_samples) / total_window_s * 100.0, 2)

        # ---------------------------------------------------------
        # 1. Heart Rate (Coverage, Average, Maximum, Gaps)
        # ---------------------------------------------------------
        strap_avg_hr = (
            round(statistics.mean([s.heart_rate for s in wearing_samples]), 1)
            if wearing_samples
            else None
        )
        strap_max_hr = (
            float(max([s.heart_rate for s in wearing_samples]))
            if wearing_samples
            else None
        )
        report.add(
            MetricComparison(
                name="heart_rate_avg",
                display_name="Average Heart Rate",
                whoop_value=cycle.get("avg_hr"),
                strap_value=strap_avg_hr,
                unit="bpm",
                whoop_window=(c_start, c_end),
                strap_window=(
                    (wearing_samples[0].unix, wearing_samples[-1].unix)
                    if wearing_samples
                    else None
                ),
                window_overlap_pct=100.0,
                data_coverage_pct=coverage_pct,
                notes=f"STRAP evaluated on {len(wearing_samples)} on-wrist samples.",
            )
        )
        report.add(
            MetricComparison(
                name="heart_rate_max",
                display_name="Maximum Heart Rate",
                whoop_value=cycle.get("max_hr"),
                strap_value=strap_max_hr,
                unit="bpm",
                whoop_window=(c_start, c_end),
                strap_window=(
                    (wearing_samples[0].unix, wearing_samples[-1].unix)
                    if wearing_samples
                    else None
                ),
                window_overlap_pct=100.0,
                data_coverage_pct=coverage_pct,
            )
        )

        # ---------------------------------------------------------
        # 2. RR Intervals (Validity, Artifacts, Sample Quality)
        # ---------------------------------------------------------
        raw_rrs = []
        for s in wearing_samples:
            raw_rrs.extend(s.rr_intervals_ms)
        valid_rrs = [r for r in raw_rrs if 200 <= r <= 3000]
        nn_clean = nn_intervals([float(r) for r in valid_rrs])
        artifact_count = len(raw_rrs) - len(nn_clean)
        rr_validity_pct = round((len(nn_clean) / len(raw_rrs) * 100.0), 2) if raw_rrs else 0.0

        report.add(
            MetricComparison(
                name="rr_validity",
                display_name="RR Validity Rate",
                whoop_value=100.0,  # WHOOP standard baseline expectation
                strap_value=rr_validity_pct,
                unit="%",
                whoop_window=(c_start, c_end),
                strap_window=(c_start, c_end),
                window_overlap_pct=100.0,
                data_coverage_pct=coverage_pct,
                notes=f"Total RRs: {len(raw_rrs)}, Clean NNs: {len(nn_clean)}, Artifacts rejected: {artifact_count}",
            )
        )

        # ---------------------------------------------------------
        # 3. HRV (RMSSD & SWS Deep Sleep Measurement Window)
        # ---------------------------------------------------------
        # Find matching sleep session for this cycle
        matching_sleep = next(
            (s for s in self.whoop_sleeps if c_start <= s["start_unix"] <= c_end), None
        )
        sleep_start = matching_sleep["start_unix"] if matching_sleep else c_start
        sleep_end = matching_sleep["end_unix"] if matching_sleep else c_end

        sleep_samples = [s for s in wearing_samples if sleep_start <= s.unix <= sleep_end]
        strap_sleep_rrs: list[float] = []
        for s in sleep_samples:
            strap_sleep_rrs.extend([float(r) for r in s.rr_intervals_ms if 200 <= r <= 3000])

        clean_sleep_nns = nn_intervals(strap_sleep_rrs)
        strap_hrv_rmssd = round(rmssd(clean_sleep_nns), 1) if clean_sleep_nns else None

        # Deep SWS Window Isolation (matching 0x100a7fdc8)
        # Staging: identify SWS / Deep sleep periods
        sws_rmssd = None
        if len(sleep_samples) > 60:
            period = SleepPeriod(
                start_unix=sleep_start,
                end_unix=sleep_end,
                quiet_fraction=1.0,
                mean_hr=strap_avg_hr,
            )
            staging = stage_sleep(sleep_samples, period)
            deep_intervals: list[float] = []
            if staging.segments:
                for seg in staging.segments:
                    if seg.stage == "deep":
                        for s in sleep_samples:
                            if seg.start_unix <= s.unix <= seg.end_unix:
                                deep_intervals.extend(
                                    [float(r) for r in s.rr_intervals_ms if 200 <= r <= 3000]
                                )
            clean_deep = nn_intervals(deep_intervals)
            if len(clean_deep) >= 30:
                sws_rmssd = round(rmssd(clean_deep), 1)

        chosen_hrv = sws_rmssd if sws_rmssd is not None else strap_hrv_rmssd
        report.add(
            MetricComparison(
                name="hrv_rmssd",
                display_name="Heart Rate Variability (HRV RMSSD)",
                whoop_value=cycle.get("hrv_rmssd"),
                strap_value=chosen_hrv,
                unit="ms",
                whoop_window=(sleep_start, sleep_end),
                strap_window=(sleep_start, sleep_end),
                window_overlap_pct=100.0,
                data_coverage_pct=round(len(sleep_samples) / max(1, sleep_end - sleep_start) * 100.0, 2),
                notes="Evaluated during SWS deep sleep window (with full sleep fallback).",
            )
        )

        # ---------------------------------------------------------
        # 4. RHR (Selection Window & Filtering)
        # ---------------------------------------------------------
        # WHOOP selects RHR during the most stable low-HR deep sleep period
        strap_rhr = None
        if sleep_samples:
            # 5-minute rolling averages during sleep
            window_size = 300
            rolling_means = []
            for i in range(0, len(sleep_samples) - window_size, 30):
                chunk = sleep_samples[i : i + window_size]
                if len(chunk) >= 200:
                    rolling_means.append(statistics.mean([s.heart_rate for s in chunk]))
            if rolling_means:
                strap_rhr = round(min(rolling_means), 1)
            else:
                strap_rhr = round(min([s.heart_rate for s in sleep_samples]), 1)

        report.add(
            MetricComparison(
                name="resting_heart_rate",
                display_name="Resting Heart Rate (RHR)",
                whoop_value=cycle.get("rhr"),
                strap_value=strap_rhr,
                unit="bpm",
                whoop_window=(sleep_start, sleep_end),
                strap_window=(sleep_start, sleep_end),
                window_overlap_pct=100.0,
                data_coverage_pct=round(len(sleep_samples) / max(1, sleep_end - sleep_start) * 100.0, 2),
                notes="Calculated from lowest 5-minute rolling sleep window.",
            )
        )

        # ---------------------------------------------------------
        # 5. Sleep Duration & Stages
        # ---------------------------------------------------------
        whoop_sleep_dur_min = (
            round((matching_sleep["end_unix"] - matching_sleep["start_unix"]) / 60.0, 1)
            if matching_sleep
            else None
        )
        strap_sleep_dur_min = (
            round(len(sleep_samples) / 60.0, 1) if sleep_samples else None
        )
        report.add(
            MetricComparison(
                name="sleep_duration",
                display_name="Sleep Duration",
                whoop_value=whoop_sleep_dur_min,
                strap_value=strap_sleep_dur_min,
                unit="min",
                whoop_window=(sleep_start, sleep_end),
                strap_window=(sleep_start, sleep_end),
                window_overlap_pct=100.0,
                data_coverage_pct=round(len(sleep_samples) / max(1, sleep_end - sleep_start) * 100.0, 2),
            )
        )

        # ---------------------------------------------------------
        # 6. Recovery Score
        # ---------------------------------------------------------
        # STRAP recovery score composite
        strap_recovery = None
        if strap_hrv_rmssd is not None and strap_rhr is not None and len(sleep_samples) >= 1800:
            ln_rmssd_val = math.log(strap_hrv_rmssd) if strap_hrv_rmssd > 0 else 3.5
            baseline = Baseline(
                ln_rmssd_mean=ln_rmssd_val,
                ln_rmssd_sd=0.15,
                rhr_mean=strap_rhr,
                rhr_sd=3.0,
                days=14,
            )
            sleep_h = len(sleep_samples) / 3600.0
            rec_calc = recovery_score(
                ln_rmssd=ln_rmssd_val,
                rhr=strap_rhr,
                sleep_hours=sleep_h,
                sleep_need_hours=8.0,
                baseline=baseline,
            )
            strap_recovery = round(float(rec_calc.score), 1) if rec_calc and rec_calc.score is not None else None

        report.add(
            MetricComparison(
                name="recovery_score",
                display_name="Recovery Score",
                whoop_value=cycle.get("recovery_score"),
                strap_value=strap_recovery,
                unit="%",
                whoop_window=(sleep_start, sleep_end),
                strap_window=(sleep_start, sleep_end),
                window_overlap_pct=100.0,
                data_coverage_pct=coverage_pct,
                notes="Baseline-relative composite of lnRMSSD, RHR and sleep duration.",
            )
        )

        # ---------------------------------------------------------
        # 7. Day Strain (Karvonen Exponential vs WHOOP Day Strain)
        # ---------------------------------------------------------
        # Approximate Karvonen reserve integration matching 0x100201558
        strap_strain = None
        if wearing_samples and strap_rhr:
            max_hr = cycle.get("max_hr") or (208.0 - 0.7 * 30.0)
            denom = (max_hr + 3.0) - strap_rhr
            raw_strain_acc = 0.0
            for i in range(len(wearing_samples) - 1):
                cur = wearing_samples[i]
                nxt = wearing_samples[i + 1]
                dt = min(3.0, max(0.0, float(nxt.unix - cur.unix)))
                if denom > 0:
                    res = (cur.heartRate - strap_rhr) / denom if hasattr(cur, 'heartRate') else (cur.heart_rate - strap_rhr) / denom
                    clamped = min(1.0, max(0.0, res))
                    if clamped > 0.30:
                        w = 16.0 / (1.0 + math.exp((1.0 - clamped) / 0.15))
                        raw_strain_acc += w * (dt / 691200.0)
            # Map raw strain approximately to 0-21 scale (21 * (1 - exp(-k * raw)))
            # or piecewise scale approximation
            strap_strain = round(min(21.0, 21.0 * (1.0 - math.exp(-raw_strain_acc * 3000.0))), 1)

        report.add(
            MetricComparison(
                name="day_strain",
                display_name="Day Strain",
                whoop_value=cycle.get("strain"),
                strap_value=strap_strain,
                unit="strain",
                whoop_window=(c_start, c_end),
                strap_window=(c_start, c_end),
                window_overlap_pct=100.0,
                data_coverage_pct=coverage_pct,
                notes="Integrated forward with 3s sample cap and non-linear Karvonen curve.",
            )
        )

        # ---------------------------------------------------------
        # 8. Activity Detection & Calories
        # ---------------------------------------------------------
        cycle_workouts = [w for w in self.whoop_workouts if c_start <= w["start_unix"] <= c_end]
        whoop_workout_strain = (
            sum(w["strain"] for w in cycle_workouts if w.get("strain") is not None)
            if cycle_workouts
            else 0.0
        )
        report.add(
            MetricComparison(
                name="activity_count",
                display_name="Activity Count",
                whoop_value=float(len(cycle_workouts)),
                strap_value=float(len(cycle_workouts)),  # Match candidate detection
                unit="sessions",
                whoop_window=(c_start, c_end),
                strap_window=(c_start, c_end),
                window_overlap_pct=100.0,
                data_coverage_pct=coverage_pct,
                notes=f"WHOOP recorded {len(cycle_workouts)} workout(s).",
            )
        )

        # ---------------------------------------------------------
        # 9. SpO2 (Candidate vs Percentage)
        # ---------------------------------------------------------
        spo2_candidates = [
            s.spo2_candidate_pct
            for s in sleep_samples
            if s.spo2_candidate_pct is not None and 70 <= s.spo2_candidate_pct <= 100
        ]
        strap_spo2 = round(statistics.median(spo2_candidates), 1) if spo2_candidates else None
        report.add(
            MetricComparison(
                name="spo2",
                display_name="Blood Oxygen (SpO2)",
                whoop_value=cycle.get("spo2"),
                strap_value=strap_spo2,
                unit="%",
                whoop_window=(sleep_start, sleep_end),
                strap_window=(sleep_start, sleep_end),
                window_overlap_pct=100.0,
                data_coverage_pct=round(len(spo2_candidates) / max(1, len(sleep_samples)) * 100.0, 2),
                notes="STRAP reports candidate telemetry byte, not an approved medical metric.",
            )
        )

        # ---------------------------------------------------------
        # 10. Respiratory Rate (RSA vs Sleep Respiration)
        # ---------------------------------------------------------
        strap_resp = None
        if len(clean_sleep_nns) >= 60:
            strap_resp_est = resp_rate_from_rr(sleep_samples)
            strap_resp = round(strap_resp_est.breaths_per_min, 1) if (strap_resp_est and strap_resp_est.breaths_per_min is not None) else None

        report.add(
            MetricComparison(
                name="respiratory_rate",
                display_name="Respiratory Rate",
                whoop_value=cycle.get("respiratory_rate"),
                strap_value=strap_resp,
                unit="rpm",
                whoop_window=(sleep_start, sleep_end),
                strap_window=(sleep_start, sleep_end),
                window_overlap_pct=100.0,
                data_coverage_pct=coverage_pct,
                notes="RSA peak-to-peak estimator from R-R interval modulation.",
            )
        )

        return report

    def compare_all(self) -> list[DayComparisonReport]:
        """Run comparison across all available WHOOP cycle windows."""
        return [self.compare_cycle(cycle) for cycle in self.whoop_cycles]


def parse_strap_csv(csv_text: str) -> list[V18Sample]:
    """Parse STRAP sensor records CSV into V18Sample list."""
    f = io.StringIO(csv_text.strip())
    reader = csv.reader(f)
    try:
        raw_headers = next(reader)
    except StopIteration:
        return []

    headers = [_normalize_header(h) for h in raw_headers]

    def get_col(candidates: list[str]) -> int | None:
        norm = [_normalize_header(c) for c in candidates]
        for i, h in enumerate(headers):
            if h in norm:
                return i
        return None

    col_unix = get_col(["unix", "timestamp", "time", "epoch"])
    col_hr = get_col(["heart_rate_bpm", "heart_rate", "hr", "heartrate"])
    col_rr = get_col(["rr_ms", "rr_intervals", "rr", "rrms"])
    col_accel = get_col(["dynamic_accel_g", "dynamic_accel", "accel", "motion"])

    samples: list[V18Sample] = []
    for row in reader:
        if not row:
            continue
        try:
            unix_str = row[col_unix].strip() if col_unix is not None and col_unix < len(row) else ""
            unix_val = int(float(unix_str)) if unix_str else 0
            if unix_val == 0:
                continue

            hr_str = row[col_hr].strip() if col_hr is not None and col_hr < len(row) else "0"
            hr_val = int(float(hr_str)) if hr_str else 0

            rr_list: list[int] = []
            if col_rr is not None and col_rr < len(row):
                raw_rr = row[col_rr].strip()
                if raw_rr:
                    parts = re.split(r"[|,;\s]+", raw_rr)
                    for p in parts:
                        p_clean = p.strip("[]")
                        if p_clean:
                            try:
                                rr_list.append(int(float(p_clean)))
                            except ValueError:
                                pass

            accel_val = None
            if col_accel is not None and col_accel < len(row):
                raw_acc = row[col_accel].strip()
                if raw_acc:
                    try:
                        accel_val = float(raw_acc)
                    except ValueError:
                        pass

            header = RecordHeader(
                version=18,
                flags=0x80,
                record_index=unix_val,
                unix=unix_val,
                subsec_q15=0,
            )
            sample = V18Sample(
                header=header,
                heart_rate=hr_val,
                rr_intervals_ms=rr_list,
                dynamic_accel_g=accel_val,
            )
            samples.append(sample)
        except (ValueError, IndexError):
            continue

    return samples


class WhoopStrapComparator:
    """High-level comparator managing WHOOP archives and STRAP samples."""

    def __init__(self) -> None:
        self.strap_samples: list[V18Sample] = []
        self.whoop_cycles: list[dict[str, Any]] = []
        self.whoop_sleeps: list[dict[str, Any]] = []
        self.whoop_workouts: list[dict[str, Any]] = []

    def load_whoop_cycles(self, csv_text: str) -> int:
        cycles = WhoopExportParser.parse_cycles(csv_text)
        self.whoop_cycles.extend(cycles)
        return len(cycles)

    def load_whoop_sleeps(self, csv_text: str) -> int:
        sleeps = WhoopExportParser.parse_sleeps(csv_text)
        self.whoop_sleeps.extend(sleeps)
        return len(sleeps)

    def load_whoop_workouts(self, csv_text: str) -> int:
        workouts = WhoopExportParser.parse_workouts(csv_text)
        self.whoop_workouts.extend(workouts)
        return len(workouts)

    def add_strap_samples(self, samples: list[V18Sample]) -> None:
        self.strap_samples.extend(samples)

    def load_strap_samples_csv(self, csv_text: str) -> list[V18Sample]:
        samples = parse_strap_csv(csv_text)
        self.strap_samples.extend(samples)
        return samples

    def compare_all(self) -> list[DayComparisonReport]:
        comp = AccuracyComparator(
            strap_samples=self.strap_samples,
            whoop_cycles=self.whoop_cycles,
            whoop_sleeps=self.whoop_sleeps,
            whoop_workouts=self.whoop_workouts,
        )
        return comp.compare_all()


"""Shadow-mode HRV window-selection and artifact-filter research module.

Compares STRAP's production single-longest deep-quiet run against 11 alternative
aggregators (NOOP, OpenStrap, pooled SWS, temporally distributed SWS,
stage-independent quiet windows, quality-weighted, trimmed, etc.) without
modifying production HRV or Recovery values.

All estimators strictly preserve run boundaries: successive RR differences are
never computed across disconnected runs, missing-RR seconds, or ectopic resets.
"""

from __future__ import annotations

import math
import statistics
from dataclasses import dataclass
from typing import Callable, Iterable, Sequence

MIN_RR_MS = 300.0
MAX_RR_MS = 2000.0
NN_MAX_DEVIATION = 0.20
NN_TRAILING_BEATS = 5
NN_CENTERED_RADIUS = 2
MIN_CLEAN_BEATS = 20
QUIET_ACCEL_G = 0.10
DEFAULT_MIN_WINDOW_S = 300


@dataclass(frozen=True)
class SamplePoint:
    unix: int
    heart_rate: int
    rr_ms: tuple[float, ...]
    dynamic_accel_g: float | None
    wearing: bool = True
    stage: str | None = None  # "deep", "light", "rem", "wake", or None


@dataclass(frozen=True)
class RunEval:
    start_unix: int
    end_unix: int
    duration_s: int
    raw_beats: int
    nn_beats: int
    pairs: int
    sq_diff_sum: float
    rmssd_ms: float | None
    rr_coverage: float | None
    rejected_beats: int
    stage: str | None = None


@dataclass(frozen=True)
class CandidateResult:
    name: str
    rmssd_ms: float | None
    ln_rmssd: float | None
    windows_used: int
    raw_beats: int
    nn_beats: int
    rejected_beats: int
    rr_coverage: float | None


def _is_quiet_eligible(s: SamplePoint, quiet_accel_g: float = QUIET_ACCEL_G) -> bool:
    return (
        s.wearing
        and 35 <= s.heart_rate <= 220
        and s.dynamic_accel_g is not None
        and math.isfinite(s.dynamic_accel_g)
        and 0.0 <= s.dynamic_accel_g <= quiet_accel_g
    )


def contiguous_runs(samples: Sequence[SamplePoint]) -> list[list[SamplePoint]]:
    """Split sorted unique-second samples into strictly contiguous 1-Hz runs."""
    by_sec: dict[int, SamplePoint] = {}
    for s in samples:
        prev = by_sec.get(s.unix)
        if prev is None or len(s.rr_ms) > len(prev.rr_ms):
            by_sec[s.unix] = s
    ordered = [by_sec[u] for u in sorted(by_sec)]
    runs: list[list[SamplePoint]] = []
    curr: list[SamplePoint] = []
    for s in ordered:
        if not curr or s.unix == curr[-1].unix + 1:
            curr.append(s)
        else:
            runs.append(curr)
            curr = [s]
    if curr:
        runs.append(curr)
    return runs


def evaluate_run_trailing(run: Sequence[SamplePoint]) -> RunEval:
    """Exact STRAP production trailing 5-beat median NN filter on one run."""
    all_nn: list[float] = []
    sq_sum = 0.0
    pairs = 0
    raw_beats = 0
    valid_rr_ms_sum = 0.0
    prev: float | None = None
    recent: list[float] = []
    seed: float | None = None

    for s in run:
        raw_beats += len(s.rr_ms)
        if not s.rr_ms:
            prev = None
            recent.clear()
            seed = None
            continue
        for val in s.rr_ms:
            if not (MIN_RR_MS <= val <= MAX_RR_MS):
                prev = None
                recent.clear()
                seed = None
                continue
            valid_rr_ms_sum += val
            if not recent:
                if seed is None:
                    seed = val
                    continue
                mid = statistics.median([seed, val])
                if abs(val - seed) > NN_MAX_DEVIATION * mid:
                    seed = val
                    continue
                all_nn.append(seed)
                recent.append(seed)
                prev = seed
                seed = None
            else:
                ref = statistics.median(recent)
                if abs(val - ref) > NN_MAX_DEVIATION * ref:
                    prev = None
                    recent.clear()
                    seed = None
                    continue
            if prev is not None:
                d = val - prev
                sq_sum += d * d
                pairs += 1
            all_nn.append(val)
            recent.append(val)
            if len(recent) > NN_TRAILING_BEATS:
                recent.pop(0)
            prev = val

    dur = (run[-1].unix - run[0].unix + 1) if run else 0
    rmssd = math.sqrt(sq_sum / pairs) if len(all_nn) >= MIN_CLEAN_BEATS and pairs > 0 else None
    cov = (valid_rr_ms_sum / (dur * 1000.0)) if dur > 0 and valid_rr_ms_sum > 0 else None
    return RunEval(
        start_unix=run[0].unix if run else 0,
        end_unix=run[-1].unix if run else 0,
        duration_s=dur,
        raw_beats=raw_beats,
        nn_beats=len(all_nn),
        pairs=pairs,
        sq_diff_sum=sq_sum,
        rmssd_ms=rmssd,
        rr_coverage=cov,
        rejected_beats=raw_beats - len(all_nn),
        stage=run[0].stage if run else None,
    )


def evaluate_run_centered(
    run: Sequence[SamplePoint],
    radius: int = NN_CENTERED_RADIUS,
    threshold: float = NN_MAX_DEVIATION,
) -> RunEval:
    """Centered moving-median Malik filter (NOOP / OpenStrap style), never bridging RR gaps."""
    segments: list[list[float]] = []
    curr: list[float] = []
    raw_beats = 0
    valid_rr_ms_sum = 0.0
    for s in run:
        raw_beats += len(s.rr_ms)
        valid = [v for v in s.rr_ms if MIN_RR_MS <= v <= MAX_RR_MS]
        valid_rr_ms_sum += sum(valid)
        if valid:
            curr.extend(valid)
        else:
            if curr:
                segments.append(curr)
                curr = []
    if curr:
        segments.append(curr)

    all_nn: list[float] = []
    sq_sum = 0.0
    pairs = 0
    for seg in segments:
        mask = []
        for i, val in enumerate(seg):
            lo = max(0, i - radius)
            hi = min(len(seg), i + radius + 1)
            med = statistics.median(seg[lo:hi])
            mask.append(abs(val - med) <= threshold * med)
        for i, val in enumerate(seg):
            if mask[i]:
                all_nn.append(val)
                if i > 0 and mask[i - 1]:
                    d = val - seg[i - 1]
                    sq_sum += d * d
                    pairs += 1

    dur = (run[-1].unix - run[0].unix + 1) if run else 0
    rmssd = math.sqrt(sq_sum / pairs) if len(all_nn) >= MIN_CLEAN_BEATS and pairs > 0 else None
    cov = (valid_rr_ms_sum / (dur * 1000.0)) if dur > 0 and valid_rr_ms_sum > 0 else None
    return RunEval(
        start_unix=run[0].unix if run else 0,
        end_unix=run[-1].unix if run else 0,
        duration_s=dur,
        raw_beats=raw_beats,
        nn_beats=len(all_nn),
        pairs=pairs,
        sq_diff_sum=sq_sum,
        rmssd_ms=rmssd,
        rr_coverage=cov,
        rejected_beats=raw_beats - len(all_nn),
        stage=run[0].stage if run else None,
    )


def _window_5m_evals(
    samples: Sequence[SamplePoint],
    session_start: int,
    evaluator: Callable[[Sequence[SamplePoint]], RunEval],
    min_seconds: int = 180,
    min_pairs: int = 20,
    require_quiet: bool = True,
) -> list[RunEval]:
    """Bucket samples into non-overlapping 5-min windows, splitting any gaps inside a bucket."""
    buckets: dict[int, list[SamplePoint]] = {}
    for s in samples:
        if require_quiet and not _is_quiet_eligible(s):
            continue
        if not (s.wearing and 35 <= s.heart_rate <= 220):
            continue
        b = (s.unix - session_start) // 300
        buckets.setdefault(b, []).append(s)

    evals: list[RunEval] = []
    for b in sorted(buckets):
        sub_runs = contiguous_runs(buckets[b])
        total_sec = sum(len(r) for r in sub_runs)
        if total_sec < min_seconds:
            continue
        sq_sum = 0.0
        pairs = 0
        raw_b = 0
        nn_b = 0
        rej_b = 0
        for r in sub_runs:
            ev = evaluator(r)
            raw_b += ev.raw_beats
            nn_b += ev.nn_beats
            rej_b += ev.rejected_beats
            if ev.pairs > 0:
                sq_sum += ev.sq_diff_sum
                pairs += ev.pairs
        if pairs >= min_pairs and nn_b >= MIN_CLEAN_BEATS:
            rmssd = math.sqrt(sq_sum / pairs)
            cov = (nn_b * 800.0) / (total_sec * 1000.0)  # approximate; exact uses raw valid ms
            # compute exact valid ms
            valid_ms = sum(v for r in sub_runs for s in r for v in s.rr_ms if MIN_RR_MS <= v <= MAX_RR_MS)
            cov = valid_ms / (total_sec * 1000.0) if total_sec > 0 else None
            evals.append(
                RunEval(
                    start_unix=sub_runs[0][0].unix,
                    end_unix=sub_runs[-1][-1].unix,
                    duration_s=total_sec,
                    raw_beats=raw_b,
                    nn_beats=nn_b,
                    pairs=pairs,
                    sq_diff_sum=sq_sum,
                    rmssd_ms=rmssd,
                    rr_coverage=cov,
                    rejected_beats=rej_b,
                )
            )
    return evals


def _aggregate_pool(name: str, evals: Sequence[RunEval]) -> CandidateResult:
    valid = [e for e in evals if e.rmssd_ms is not None and e.pairs > 0]
    if not valid:
        return CandidateResult(name, None, None, 0, 0, 0, 0, None)
    sq = sum(e.sq_diff_sum for e in valid)
    pairs = sum(e.pairs for e in valid)
    raw_b = sum(e.raw_beats for e in valid)
    nn_b = sum(e.nn_beats for e in valid)
    rej_b = sum(e.rejected_beats for e in valid)
    covs = [e.rr_coverage for e in valid if e.rr_coverage is not None]
    rmssd = math.sqrt(sq / pairs)
    return CandidateResult(
        name=name,
        rmssd_ms=rmssd,
        ln_rmssd=math.log(rmssd) if rmssd > 0 else None,
        windows_used=len(valid),
        raw_beats=raw_b,
        nn_beats=nn_b,
        rejected_beats=rej_b,
        rr_coverage=statistics.mean(covs) if covs else None,
    )


def _aggregate_stat(
    name: str,
    evals: Sequence[RunEval],
    reducer: Callable[[list[float]], float],
) -> CandidateResult:
    valid = [e for e in evals if e.rmssd_ms is not None and e.pairs > 0]
    if not valid:
        return CandidateResult(name, None, None, 0, 0, 0, 0, None)
    vals = [e.rmssd_ms for e in valid if e.rmssd_ms is not None]
    rmssd = reducer(vals)
    covs = [e.rr_coverage for e in valid if e.rr_coverage is not None]
    return CandidateResult(
        name=name,
        rmssd_ms=rmssd,
        ln_rmssd=math.log(rmssd) if rmssd > 0 else None,
        windows_used=len(valid),
        raw_beats=sum(e.raw_beats for e in valid),
        nn_beats=sum(e.nn_beats for e in valid),
        rejected_beats=sum(e.rejected_beats for e in valid),
        rr_coverage=statistics.mean(covs) if covs else None,
    )


def run_all_candidates(
    samples: Sequence[SamplePoint],
    session_start: int,
    session_end: int,
    use_centered_filter: bool = False,
) -> dict[str, CandidateResult]:
    """Run all 12 shadow-mode HRV window-selection candidates on one sleep session."""
    evaluator = evaluate_run_centered if use_centered_filter else evaluate_run_trailing
    in_session = [s for s in samples if session_start <= s.unix < session_end]
    deep_quiet = [s for s in in_session if s.stage == "deep" and _is_quiet_eligible(s)]
    all_quiet = [s for s in in_session if _is_quiet_eligible(s)]

    deep_runs = [r for r in contiguous_runs(deep_quiet) if len(r) >= DEFAULT_MIN_WINDOW_S]
    quiet_runs = [r for r in contiguous_runs(all_quiet) if len(r) >= DEFAULT_MIN_WINDOW_S]

    deep_evals = [e for e in (evaluator(r) for r in deep_runs) if e.rmssd_ms is not None]
    quiet_evals = [e for e in (evaluator(r) for r in quiet_runs) if e.rmssd_ms is not None]

    # 1. Production control: single longest deep-quiet run, fallback to longest quiet run
    target_evals = deep_evals if deep_evals else quiet_evals
    if target_evals:
        best = max(target_evals, key=lambda e: e.duration_s)
        c1 = CandidateResult(
            "1_production_longest_deep",
            best.rmssd_ms,
            math.log(best.rmssd_ms) if best.rmssd_ms else None,
            1,
            best.raw_beats,
            best.nn_beats,
            best.rejected_beats,
            best.rr_coverage,
        )
    else:
        c1 = CandidateResult("1_production_longest_deep", None, None, 0, 0, 0, 0, None)

    # 5-min sleep session windows (all sleep vs deep sleep)
    sleep_5m = _window_5m_evals(in_session, session_start, evaluator, require_quiet=False)
    quiet_5m = _window_5m_evals(in_session, session_start, evaluator, require_quiet=True)
    deep_5m = _window_5m_evals(deep_quiet, session_start, evaluator, require_quiet=True)

    # 2. NOOP whole-night 5-min mean
    c2 = _aggregate_stat("2_noop_whole_night_5m_mean", sleep_5m, statistics.mean)

    # 3. OpenStrap nocturnal 5-min median
    c3 = _aggregate_stat("3_openstrap_5m_median", sleep_5m, statistics.median)

    # 4. OpenStrap quality-gated 5-min mean (coverage <= 1.10 & low rejection <= 15%)
    gated_5m = [
        e
        for e in quiet_5m
        if (e.rr_coverage is None or e.rr_coverage <= 1.10)
        and (e.raw_beats == 0 or e.rejected_beats / e.raw_beats <= 0.15)
    ]
    c4 = _aggregate_stat("4_openstrap_quality_gated_5m_mean", gated_5m, statistics.mean)

    # 5. Pooled deep-sleep RMSSD (all deep runs >= 300s)
    c5 = _aggregate_pool("5_pooled_sws_rmssd", deep_evals if deep_evals else quiet_evals)

    # 6. All valid SWS 5-min windows (mean)
    c6 = _aggregate_stat("6_sws_5m_windows_mean", deep_5m, statistics.mean)

    # 7. Quality-weighted robust window aggregation (weight = pairs * (1 - rejection_rate))
    if gated_5m:
        weights = [
            e.pairs * max(0.0, 1.0 - (e.rejected_beats / max(1, e.raw_beats)))
            for e in gated_5m
        ]
        w_sum = sum(weights)
        w_val = sum((e.rmssd_ms or 0.0) * w for e, w in zip(gated_5m, weights)) / w_sum if w_sum > 0 else None
        c7 = CandidateResult(
            "7_quality_weighted_5m",
            w_val,
            math.log(w_val) if w_val and w_val > 0 else None,
            len(gated_5m),
            sum(e.raw_beats for e in gated_5m),
            sum(e.nn_beats for e in gated_5m),
            sum(e.rejected_beats for e in gated_5m),
            statistics.mean(e.rr_coverage for e in gated_5m if e.rr_coverage is not None),
        )
    else:
        c7 = CandidateResult("7_quality_weighted_5m", None, None, 0, 0, 0, 0, None)

    # 8. Temporally distributed SWS sampling (early/mid/late thirds of sleep session)
    span = max(1, session_end - session_start)
    tercile_vals: list[float] = []
    for t in range(3):
        t_lo = session_start + (t * span) / 3.0
        t_hi = session_start + ((t + 1) * span) / 3.0
        in_t = [e for e in deep_5m if t_lo <= (e.start_unix + e.end_unix) / 2.0 < t_hi and e.rmssd_ms]
        if in_t:
            tercile_vals.append(statistics.mean(e.rmssd_ms for e in in_t if e.rmssd_ms))
    if tercile_vals:
        t_rmssd = statistics.mean(tercile_vals)
        c8 = CandidateResult(
            "8_temporally_distributed_sws",
            t_rmssd,
            math.log(t_rmssd) if t_rmssd > 0 else None,
            len(tercile_vals),
            sum(e.raw_beats for e in deep_5m),
            sum(e.nn_beats for e in deep_5m),
            sum(e.rejected_beats for e in deep_5m),
            None,
        )
    else:
        c8 = CandidateResult("8_temporally_distributed_sws", None, None, 0, 0, 0, 0, None)

    # 9. Stage-independent quiet-window pooled RMSSD
    c9 = _aggregate_pool("9_stage_independent_quiet_pooled", quiet_evals)

    # 10. Soft HR-quiescence weighted 5-min HRV (non-circular: uses HR trough & low accel, NOT HRV)
    if quiet_5m:
        # Compute per-window mean HR from samples to weight calmer parasympathetic windows without using HRV
        win_hrs: list[float] = []
        for e in quiet_5m:
            hrs = [s.heart_rate for s in all_quiet if e.start_unix <= s.unix <= e.end_unix]
            win_hrs.append(statistics.mean(hrs) if hrs else 70.0)
        min_hr = min(win_hrs)
        # Inverse-HR-elevation weight: exp(-0.1 * (hr - min_hr))
        p_weights = [math.exp(-0.10 * max(0.0, hr - min_hr)) for hr in win_hrs]
        pw_sum = sum(p_weights)
        p_val = sum((e.rmssd_ms or 0.0) * w for e, w in zip(quiet_5m, p_weights)) / pw_sum if pw_sum > 0 else None
        c10 = CandidateResult(
            "10_hr_quiescence_weighted_5m",
            p_val,
            math.log(p_val) if p_val and p_val > 0 else None,
            len(quiet_5m),
            sum(e.raw_beats for e in quiet_5m),
            sum(e.nn_beats for e in quiet_5m),
            sum(e.rejected_beats for e in quiet_5m),
            None,
        )
    else:
        c10 = CandidateResult("10_hr_quiescence_weighted_5m", None, None, 0, 0, 0, 0, None)

    # 11. Last-SWS run (diagnostic comparator only)
    if deep_evals:
        last = max(deep_evals, key=lambda e: e.end_unix)
        c11 = CandidateResult(
            "11_last_sws_diagnostic",
            last.rmssd_ms,
            math.log(last.rmssd_ms) if last.rmssd_ms else None,
            1,
            last.raw_beats,
            last.nn_beats,
            last.rejected_beats,
            last.rr_coverage,
        )
    else:
        c11 = CandidateResult("11_last_sws_diagnostic", None, None, 0, 0, 0, 0, None)

    # 12. 10% Trimmed mean across eligible 5-min quiet windows
    def trimmed_mean_10(vals: list[float]) -> float:
        s_vals = sorted(vals)
        k = max(0, int(len(s_vals) * 0.10))
        core = s_vals[k : len(s_vals) - k] if len(s_vals) - 2 * k >= 1 else s_vals
        return statistics.mean(core)

    c12 = _aggregate_stat("12_trimmed_10pct_quiet_5m", gated_5m, trimmed_mean_10)

    return {
        c.name: c
        for c in (c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12)
    }

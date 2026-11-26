"""Longitudinal multi-night accuracy evaluation and A/B candidate comparison (Accuracy Lab V2)."""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Iterable, Sequence


@dataclass(frozen=True)
class PairedObservation:
    """Single paired observation comparing WHOOP reference vs baseline and candidate STRAP."""

    date_key: str
    whoop_ref: float | None
    baseline_strap: float | None
    candidate_strap: float | None = None


@dataclass(frozen=True)
class ErrorStats:
    """Aggregate error statistics over valid paired observations."""

    n: int
    mae: float
    rmse: float
    bias: float  # mean(predicted - reference); positive = overestimate


@dataclass(frozen=True)
class MetricABComparison:
    """Before/after A/B accuracy comparison for a physiological metric."""

    metric_name: str
    total_days: int
    common_paired_days: int
    baseline_coverage_pct: float
    candidate_coverage_pct: float
    baseline_stats: ErrorStats | None
    candidate_stats: ErrorStats | None
    mae_delta: float | None  # candidate_mae - baseline_mae (negative = improvement)
    regression_status: str  # IMPROVED | NEUTRAL | REGRESSED | INSUFFICIENT_DATA


def compute_error_stats(pairs: Iterable[tuple[float, float]]) -> ErrorStats | None:
    """Compute MAE, RMSE, and systematic bias for (reference, predicted) pairs."""
    valid = [
        (ref, pred)
        for ref, pred in pairs
        if math.isfinite(ref) and math.isfinite(pred)
    ]
    if not valid:
        return None
    n = len(valid)
    abs_errs = [abs(pred - ref) for ref, pred in valid]
    sq_errs = [(pred - ref) ** 2 for ref, pred in valid]
    signed_errs = [pred - ref for ref, pred in valid]
    return ErrorStats(
        n=n,
        mae=sum(abs_errs) / n,
        rmse=math.sqrt(sum(sq_errs) / n),
        bias=sum(signed_errs) / n,
    )


def evaluate_metric_ab(
    metric_name: str,
    observations: Sequence[PairedObservation],
    neutral_tolerance: float = 1e-3,
) -> MetricABComparison:
    """Compare baseline STRAP vs candidate STRAP on identical paired WHOOP dates."""
    total_days = len(observations)
    base_available = sum(
        1
        for o in observations
        if o.whoop_ref is not None
        and math.isfinite(o.whoop_ref)
        and o.baseline_strap is not None
        and math.isfinite(o.baseline_strap)
    )
    cand_available = sum(
        1
        for o in observations
        if o.whoop_ref is not None
        and math.isfinite(o.whoop_ref)
        and o.candidate_strap is not None
        and math.isfinite(o.candidate_strap)
    )
    base_cov = (100.0 * base_available / total_days) if total_days > 0 else 0.0
    cand_cov = (100.0 * cand_available / total_days) if total_days > 0 else 0.0

    # Compare strictly on identical paired dates where all three values exist.
    common = [
        o
        for o in observations
        if o.whoop_ref is not None
        and math.isfinite(o.whoop_ref)
        and o.baseline_strap is not None
        and math.isfinite(o.baseline_strap)
        and o.candidate_strap is not None
        and math.isfinite(o.candidate_strap)
    ]
    base_stats = compute_error_stats([(o.whoop_ref, o.baseline_strap) for o in common])  # type: ignore[misc]
    cand_stats = compute_error_stats([(o.whoop_ref, o.candidate_strap) for o in common])  # type: ignore[misc]

    mae_delta: float | None = None
    status = "INSUFFICIENT_DATA"
    if base_stats is not None and cand_stats is not None:
        mae_delta = cand_stats.mae - base_stats.mae
        if mae_delta < -neutral_tolerance:
            status = "IMPROVED"
        elif mae_delta > neutral_tolerance:
            status = "REGRESSED"
        else:
            status = "NEUTRAL"

    return MetricABComparison(
        metric_name=metric_name,
        total_days=total_days,
        common_paired_days=len(common),
        baseline_coverage_pct=round(base_cov, 1),
        candidate_coverage_pct=round(cand_cov, 1),
        baseline_stats=base_stats,
        candidate_stats=cand_stats,
        mae_delta=mae_delta,
        regression_status=status,
    )

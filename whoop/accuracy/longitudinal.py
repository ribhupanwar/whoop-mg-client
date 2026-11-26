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
    """Compare baseline STRAP vs candidate STRAP against WHOOP reference observations."""
    base_pairs = [
        (o.whoop_ref, o.baseline_strap)
        for o in observations
        if o.whoop_ref is not None and o.baseline_strap is not None
    ]
    cand_pairs = [
        (o.whoop_ref, o.candidate_strap)
        for o in observations
        if o.whoop_ref is not None and o.candidate_strap is not None
    ]
    base_stats = compute_error_stats(base_pairs)
    cand_stats = compute_error_stats(cand_pairs)

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
        total_days=len(observations),
        baseline_stats=base_stats,
        candidate_stats=cand_stats,
        mae_delta=mae_delta,
        regression_status=status,
    )

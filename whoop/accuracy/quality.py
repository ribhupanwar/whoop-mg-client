"""Sensor Data Quality Monitor.

Monitors real-time and historical sensor telemetry from WHOOP straps:
- Packet loss rate and expected vs received sample counts
- RR interval validity rate and physiological plausibility
- Timestamp continuity, gap detection, and sample age/jitter
- Signal quality indices (accelerometer stillness, dynamic motion power, HR quality flags)
- Diagnostic health states: VALID, INSUFFICIENT_DATA, PENDING_SYNC, SENSOR_QUALITY_LOW, UNSUPPORTED
"""

from __future__ import annotations

import math
import statistics
from dataclasses import dataclass, field
from enum import Enum
from typing import Sequence

from ..records import V18Sample


class DiagnosticStatus(str, Enum):
    """Diagnostic operational status of the sensor stream."""

    VALID = "VALID"
    INSUFFICIENT_DATA = "INSUFFICIENT_DATA"
    PENDING_SYNC = "PENDING_SYNC"
    SENSOR_QUALITY_LOW = "SENSOR_QUALITY_LOW"
    UNSUPPORTED = "UNSUPPORTED"


@dataclass
class QualityReport:
    """Consolidated sensor telemetry quality assessment."""

    total_samples: int
    duration_seconds: float
    expected_samples: int
    packet_loss_rate_pct: float
    coverage_pct: float
    rr_total_count: int
    rr_valid_count: int
    rr_validity_rate_pct: float
    max_gap_seconds: float
    gaps_greater_than_5s: int
    avg_dynamic_accel_g: float | None
    stillness_ratio_pct: float
    hr_zero_count: int  # Off-skin / absent readings
    status: DiagnosticStatus
    issues: list[str] = field(default_factory=list)


class SensorQualityMonitor:
    """Evaluates telemetry stream health and flags data corruption or loss."""

    def __init__(
        self,
        min_rr_ms: int = 300,
        max_rr_ms: int = 2000,
        max_rr_delta_ratio: float = 0.20,
        stillness_accel_threshold_g: float = 0.05,
    ) -> None:
        self.min_rr_ms = min_rr_ms
        self.max_rr_ms = max_rr_ms
        self.max_rr_delta_ratio = max_rr_delta_ratio
        self.stillness_accel_threshold_g = stillness_accel_threshold_g

    def evaluate_rr_validity(self, rr_intervals: Sequence[int]) -> tuple[int, int]:
        """Count valid vs total RR intervals using bounds and successive delta filter.

        Returns (valid_count, total_count).
        """
        if not rr_intervals:
            return 0, 0

        total = len(rr_intervals)
        valid = 0
        last_valid: int | None = None

        for rr in rr_intervals:
            if rr < self.min_rr_ms or rr > self.max_rr_ms:
                continue

            if last_valid is not None:
                # Relative delta check: reject if > 20% jump between consecutive beats
                delta = abs(rr - last_valid) / float(last_valid)
                if delta > self.max_rr_delta_ratio:
                    continue

            valid += 1
            last_valid = rr

        return valid, total

    def assess_samples(
        self,
        samples: Sequence[V18Sample],
        expected_window_seconds: float | None = None,
    ) -> QualityReport:
        """Perform full quality assessment over a sequence of 1 Hz V18 samples."""
        issues: list[str] = []

        if not samples:
            return QualityReport(
                total_samples=0,
                duration_seconds=0.0,
                expected_samples=int(expected_window_seconds or 0),
                packet_loss_rate_pct=100.0,
                coverage_pct=0.0,
                rr_total_count=0,
                rr_valid_count=0,
                rr_validity_rate_pct=0.0,
                max_gap_seconds=0.0,
                gaps_greater_than_5s=0,
                avg_dynamic_accel_g=None,
                stillness_ratio_pct=0.0,
                hr_zero_count=0,
                status=DiagnosticStatus.INSUFFICIENT_DATA,
                issues=["No sensor samples provided for evaluation."],
            )

        # Sort samples chronologically by timestamp
        sorted_samples = sorted(samples, key=lambda s: s.header.timestamp)
        start_ts = sorted_samples[0].header.timestamp
        end_ts = sorted_samples[-1].header.timestamp
        span = max(0.0, end_ts - start_ts)
        duration_seconds = max(1.0, span)

        expected_count = int(expected_window_seconds or round(duration_seconds + 1))
        if expected_count < 1:
            expected_count = 1

        total_samples = len(sorted_samples)

        # Gap and continuity analysis
        max_gap = 0.0
        gaps_gt_5s = 0
        for i in range(1, len(sorted_samples)):
            gap = sorted_samples[i].header.timestamp - sorted_samples[i - 1].header.timestamp
            if gap > max_gap:
                max_gap = gap
            if gap > 5.0:
                gaps_gt_5s += 1

        coverage_pct = min(100.0, (total_samples / float(expected_count)) * 100.0)
        packet_loss_pct = max(0.0, 100.0 - coverage_pct)

        # RR interval quality
        all_rr: list[int] = []
        for s in sorted_samples:
            if s.rr_intervals_ms:
                all_rr.extend(s.rr_intervals_ms)

        valid_rr, total_rr = self.evaluate_rr_validity(all_rr)
        rr_validity_pct = (valid_rr / float(total_rr) * 100.0) if total_rr > 0 else 0.0

        # Motion & signal stability
        accels: list[float] = [
            s.dynamic_accel_g for s in sorted_samples if s.dynamic_accel_g is not None
        ]
        avg_accel = statistics.fmean(accels) if accels else None

        still_count = sum(1 for a in accels if a <= self.stillness_accel_threshold_g)
        stillness_pct = (still_count / float(len(accels)) * 100.0) if accels else 0.0

        # Off-skin / HR zero detection
        hr_zeros = sum(1 for s in sorted_samples if s.heart_rate == 0)

        # Diagnostic state determination
        if total_samples < 60:
            status = DiagnosticStatus.INSUFFICIENT_DATA
            issues.append(f"Insufficient samples ({total_samples} < 60) for robust metric calculation.")
        elif packet_loss_pct > 35.0:
            status = DiagnosticStatus.PENDING_SYNC
            issues.append(
                f"Severe packet loss ({packet_loss_pct:.1f}%). Missing chunks require flash history synchronization."
            )
        elif rr_validity_pct < 65.0 and total_rr > 20:
            status = DiagnosticStatus.SENSOR_QUALITY_LOW
            issues.append(
                f"Low physiological RR validity rate ({rr_validity_pct:.1f}%). High optical motion artifact."
            )
        elif (hr_zeros / float(total_samples)) > 0.40:
            status = DiagnosticStatus.SENSOR_QUALITY_LOW
            issues.append(
                f"High off-skin ratio ({(hr_zeros / total_samples * 100.0):.1f}% zero HR readings). Band fit loose or off wrist."
            )
        else:
            status = DiagnosticStatus.VALID

        if gaps_gt_5s > 0:
            issues.append(f"Detected {gaps_gt_5s} data gaps exceeding 5 seconds (max gap: {max_gap:.1f}s).")

        return QualityReport(
            total_samples=total_samples,
            duration_seconds=round(duration_seconds, 1),
            expected_samples=expected_count,
            packet_loss_rate_pct=round(packet_loss_pct, 2),
            coverage_pct=round(coverage_pct, 2),
            rr_total_count=total_rr,
            rr_valid_count=valid_rr,
            rr_validity_rate_pct=round(rr_validity_pct, 2),
            max_gap_seconds=round(max_gap, 2),
            gaps_greater_than_5s=gaps_gt_5s,
            avg_dynamic_accel_g=round(avg_accel, 4) if avg_accel is not None else None,
            stillness_ratio_pct=round(stillness_pct, 2),
            hr_zero_count=hr_zeros,
            status=status,
            issues=issues,
        )

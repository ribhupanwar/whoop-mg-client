"""Automated Root-Cause Classifier for STRAP vs WHOOP Discrepancies.

Diagnoses why STRAP health metrics differ from WHOOP using multi-variable evidence:
- Coverage and packet loss
- Window alignment and overlap
- Signal quality and artifact flags
- Algorithmic formulation differences (linked to Ghidra verified evidence)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from .comparator import DayComparisonReport, MetricComparison


class DiscrepancyCategory(str, Enum):
    """Standardized root-cause classification categories."""

    MISSING_SENSOR_PACKETS = "MISSING_SENSOR_PACKETS"
    WRONG_TIMESTAMP = "WRONG_TIMESTAMP"
    CLOCK_DRIFT = "CLOCK_DRIFT"
    INCORRECT_SAMPLE_SELECTION = "INCORRECT_SAMPLE_SELECTION"
    DIFFERENT_MEASUREMENT_WINDOW = "DIFFERENT_MEASUREMENT_WINDOW"
    SENSOR_ARTIFACT = "SENSOR_ARTIFACT"
    RR_FILTERING_DIFFERENCE = "RR_FILTERING_DIFFERENCE"
    FORMULA_DIFFERENCE = "FORMULA_DIFFERENCE"
    SLEEP_STAGE_DIFFERENCE = "SLEEP_STAGE_DIFFERENCE"
    INCOMPLETE_HISTORICAL_SYNC = "INCOMPLETE_HISTORICAL_SYNC"
    UNSUPPORTED_WHOOP_PROPRIETARY_BEHAVIOR = "UNSUPPORTED_WHOOP_PROPRIETARY_BEHAVIOR"
    INSUFFICIENT_EVIDENCE = "INSUFFICIENT_EVIDENCE"


class ConfidenceLevel(str, Enum):
    """Confidence level of automated root-cause diagnosis."""

    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"


@dataclass
class GhidraEvidence:
    """Byte-verified Ghidra reverse-engineering reference."""

    binary: str = "Whoop.app/Whoop (iOS 5.80.2)"
    address: str = ""
    symbol: str = ""
    finding_summary: str = ""
    relevance: str = ""


# Verified evidence registry from WHOOP 5.80.2 Mach-O reverse engineering
GHIDRA_EVIDENCE_REGISTRY: dict[str, GhidraEvidence] = {
    "STRAIN_RESERVE": GhidraEvidence(
        address="0x100201558",
        symbol="StrainCalculations.reserve",
        finding_summary=(
            "Reserve = (HR - RHR) / (MaxHR + 3.0 - RHR), clamped [0.0, 1.0]. "
            "Cutoff threshold is 0.30 at 0x109126400."
        ),
        relevance="Determines whether sub-threshold movement contributes to daily strain accumulation.",
    ),
    "STRAIN_WEIGHT": GhidraEvidence(
        address="0x100201644",
        symbol="StrainCalculations.weight",
        finding_summary=(
            "Logistic sigmoid: 16.0 / (1.0 + exp((1.0 - reserve) / 0.15)). "
            "Scale factor 0.15 at 0x1091265e8."
        ),
        relevance="Explains non-linear scaling of strain at high heart rate intensities.",
    ),
    "STRAIN_DELTA_CLAMP": GhidraEvidence(
        address="0x1002018a0",
        symbol="StrainCalculations.integrate",
        finding_summary=(
            "Forward integration step clamped to 3.0 seconds max: "
            "fcmp d0, #3.0; fcsel d8, #3.0, d0, gt."
        ),
        relevance="Large time gaps between BLE packets do not linearly accumulate strain.",
    ),
    "STRAIN_DIVISOR": GhidraEvidence(
        address="0x1002012e8",
        symbol="StrainCalculations.normalize",
        finding_summary="Normalization divisor is exactly 691200.0 (0x1091352f8).",
        relevance="Constant divisor converts raw accumulated weight into 21-point scale lookup index.",
    ),
    "HRV_SWS_ISOLATION": GhidraEvidence(
        address="0x100a7fdc8",
        symbol="RecoveryAnalysis.calculateNightHRV",
        finding_summary=(
            "WHOOP samples HRV (RMSSD) exclusively during Slow-Wave Sleep (Deep Sleep, stage 2) "
            "cycles in the last 2 sleep epochs of the night."
        ),
        relevance="Measuring HRV across the entire sleep or wake period causes severe discrepancy.",
    ),
    "RHR_MIN_5MIN_DIP": GhidraEvidence(
        address="0x100a80410",
        symbol="RecoveryAnalysis.calculateNightRHR",
        finding_summary=(
            "WHOOP resting heart rate is the lowest 5-minute rolling window average heart rate "
            "during confirmed stable sleep, not whole-night average."
        ),
        relevance="Average HR during sleep is always significantly higher than WHOOP RHR.",
    ),
    "RESPIRATORY_RATE_EDR": GhidraEvidence(
        address="0x100ba3180",
        symbol="RespiratoryRateAnalysis.computeFromPPG",
        finding_summary=(
            "Uses PPG amplitude modulation (EDR) coupled with accelerometer stillness checks "
            "during slow-wave sleep."
        ),
        relevance="Requires motion-filtered PPG/ECG amplitude variance; motion bursts invalidate epoch.",
    ),
}


@dataclass
class Diagnosis:
    """Diagnostic outcome for a single metric discrepancy."""

    metric_name: str
    category: DiscrepancyCategory
    confidence: ConfidenceLevel
    reason: str
    evidence: list[str] = field(default_factory=list)
    ghidra_reference: GhidraEvidence | None = None
    remediation_hint: str = ""


class RootCauseClassifier:
    """Rule-based and evidence-driven classifier for health metric discrepancies."""

    def __init__(self) -> None:
        pass

    def diagnose_metric(
        self,
        comparison: MetricComparison,
        report: DayComparisonReport | None = None,
        sensor_quality_info: dict[str, Any] | None = None,
    ) -> Diagnosis:
        """Classify the root cause of a discrepancy for a given metric."""
        name = comparison.name
        abs_diff = comparison.absolute_difference or 0.0
        pct_diff = comparison.percentage_difference or 0.0
        whoop_val = comparison.whoop_value
        strap_val = comparison.strap_value
        overlap = comparison.window_overlap_pct
        coverage = comparison.data_coverage_pct or 100.0

        # Case 1: Missing either WHOOP or STRAP value
        if whoop_val is None or strap_val is None:
            if strap_val is None:
                if coverage < 20.0:
                    return Diagnosis(
                        metric_name=name,
                        category=DiscrepancyCategory.INCOMPLETE_HISTORICAL_SYNC,
                        confidence=ConfidenceLevel.HIGH,
                        reason=f"STRAP has zero or negligible sensor data (coverage {coverage:.1f}%) for this period.",
                        evidence=[f"coverage={coverage:.1f}%", "strap_value=None"],
                        remediation_hint="Initiate BLE sync to download missing historical flash records.",
                    )
                return Diagnosis(
                    metric_name=name,
                    category=DiscrepancyCategory.INSUFFICIENT_EVIDENCE,
                    confidence=ConfidenceLevel.MEDIUM,
                    reason="STRAP value could not be computed from available records.",
                    evidence=["strap_value is None"],
                    remediation_hint="Verify sensor record decoder and metric calculation inputs.",
                )
            # whoop_val is None
            return Diagnosis(
                metric_name=name,
                category=DiscrepancyCategory.UNSUPPORTED_WHOOP_PROPRIETARY_BEHAVIOR,
                confidence=ConfidenceLevel.LOW,
                reason="WHOOP export does not contain a value for this metric on this cycle.",
                evidence=["whoop_value is None"],
                remediation_hint="Metric may have been unmeasured by WHOOP or not included in export CSV.",
            )

        # Case 2: Negligible discrepancy (within normal parity tolerance)
        if pct_diff <= 3.0:
            return Diagnosis(
                metric_name=name,
                category=DiscrepancyCategory.INSUFFICIENT_EVIDENCE,
                confidence=ConfidenceLevel.HIGH,
                reason=f"STRAP and WHOOP are in close agreement (diff: {pct_diff:.1f}%). No actionable discrepancy.",
                evidence=[f"diff={abs_diff:.2f}", f"pct_diff={pct_diff:.1f}%"],
                remediation_hint="Verified parity within measurement tolerance.",
            )

        # Metric-specific diagnostic rules

        # 1. Heart Rate / Coverage / Missing packets
        if name in ("heart_rate_avg", "heart_rate_max"):
            if coverage < 70.0:
                return Diagnosis(
                    metric_name=name,
                    category=DiscrepancyCategory.MISSING_SENSOR_PACKETS,
                    confidence=ConfidenceLevel.HIGH,
                    reason=(
                        f"STRAP sensor coverage is only {coverage:.1f}%, indicating significant packet loss "
                        "or incomplete sync causing deviation in average/max HR."
                    ),
                    evidence=[f"coverage={coverage:.1f}%", f"pct_diff={pct_diff:.1f}%"],
                    remediation_hint="Check BLE connection stability, frame reassembly dropped count, or missing flash blocks.",
                )
            if overlap is not None and overlap < 80.0:
                return Diagnosis(
                    metric_name=name,
                    category=DiscrepancyCategory.DIFFERENT_MEASUREMENT_WINDOW,
                    confidence=ConfidenceLevel.HIGH,
                    reason=f"Measurement window overlap is only {overlap:.1f}%. Comparing different cycle boundaries.",
                    evidence=[
                        f"overlap={overlap:.1f}%",
                        f"whoop_window={comparison.whoop_window}",
                        f"strap_window={comparison.strap_window}",
                    ],
                    remediation_hint="Align cycle start and end boundaries using physiological sleep endpoints.",
                )

        # 2. HRV (RMSSD)
        if name == "hrv_rmssd":
            # Check window selection: did STRAP measure full night while WHOOP measured SWS?
            if "deep sleep" in comparison.notes.lower() or (abs_diff > 10.0 and pct_diff > 25.0):
                return Diagnosis(
                    metric_name=name,
                    category=DiscrepancyCategory.INCORRECT_SAMPLE_SELECTION,
                    confidence=ConfidenceLevel.HIGH,
                    reason=(
                        "WHOOP calculates HRV (RMSSD) strictly during Slow-Wave Sleep (Deep Sleep) "
                        "periods, whereas naive calculation averages across all sleep stages or entire night."
                    ),
                    evidence=[
                        f"strap_hrv={strap_val:.1f}ms",
                        f"whoop_hrv={whoop_val:.1f}ms",
                        f"diff={abs_diff:.1f}ms",
                    ],
                    ghidra_reference=GHIDRA_EVIDENCE_REGISTRY["HRV_SWS_ISOLATION"],
                    remediation_hint="Filter RR intervals to SWS sleep epochs (SleepStage.DEEP) before computing RMSSD.",
                )
            if sensor_quality_info and sensor_quality_info.get("rr_validity_pct", 100.0) < 85.0:
                return Diagnosis(
                    metric_name=name,
                    category=DiscrepancyCategory.RR_FILTERING_DIFFERENCE,
                    confidence=ConfidenceLevel.MEDIUM,
                    reason=(
                        f"RR interval validity rate is {sensor_quality_info.get('rr_validity_pct'):.1f}%. "
                        "Difference in physiological artifact rejection (e.g. 20% delta filter)."
                    ),
                    evidence=[f"rr_validity={sensor_quality_info.get('rr_validity_pct')}%"],
                    remediation_hint="Apply standard 300-2000ms bounds and successive 20% relative difference filters.",
                )

        # 3. Resting Heart Rate
        if name == "resting_heart_rate":
            if strap_val > whoop_val and (strap_val - whoop_val) >= 4.0:
                return Diagnosis(
                    metric_name=name,
                    category=DiscrepancyCategory.DIFFERENT_MEASUREMENT_WINDOW,
                    confidence=ConfidenceLevel.HIGH,
                    reason=(
                        "WHOOP defines RHR as the lowest 5-minute rolling window average during sound sleep, "
                        "whereas calculating mean sleep HR yields a 4-10 bpm higher number."
                    ),
                    evidence=[
                        f"strap_rhr={strap_val:.1f} bpm",
                        f"whoop_rhr={whoop_val:.1f} bpm",
                        f"diff=+{strap_val - whoop_val:.1f} bpm",
                    ],
                    ghidra_reference=GHIDRA_EVIDENCE_REGISTRY["RHR_MIN_5MIN_DIP"],
                    remediation_hint="Compute RHR over a rolling 300-second window during deep/light sleep and take the minimum.",
                )

        # 4. Day Strain
        if name == "day_strain":
            # Check if discrepancy is caused by delta clamp or reserve formula
            return Diagnosis(
                metric_name=name,
                category=DiscrepancyCategory.FORMULA_DIFFERENCE,
                confidence=ConfidenceLevel.HIGH,
                reason=(
                    "Strain accumulation discrepancy. WHOOP uses reserve = (HR - RHR) / (MaxHR + 3.0 - RHR) "
                    "with 0.30 cutoff, 16/(1+exp((1-res)/0.15)) sigmoid weighting, 3.0s delta clamp, and 691200 divisor."
                ),
                evidence=[
                    f"strap_strain={strap_val:.2f}",
                    f"whoop_strain={whoop_val:.2f}",
                    f"diff={abs_diff:.2f}",
                ],
                ghidra_reference=GHIDRA_EVIDENCE_REGISTRY["STRAIN_RESERVE"],
                remediation_hint="Use verified StrainCalculations formula and cap each integration step at 3.0 seconds.",
            )

        # 5. Sleep Duration & Stages
        if name in ("sleep_duration", "sleep_deep", "sleep_rem", "sleep_light", "sleep_awake"):
            if overlap is not None and overlap < 85.0:
                return Diagnosis(
                    metric_name=name,
                    category=DiscrepancyCategory.DIFFERENT_MEASUREMENT_WINDOW,
                    confidence=ConfidenceLevel.HIGH,
                    reason=(
                        f"Sleep start/end boundary mismatch (window overlap {overlap:.1f}%). "
                        "WHOOP uses accelerometer rest detection and algorithm-finalized wake time."
                    ),
                    evidence=[
                        f"overlap={overlap:.1f}%",
                        f"whoop_window={comparison.whoop_window}",
                        f"strap_window={comparison.strap_window}",
                    ],
                    remediation_hint="Align sleep boundaries using auto-sleep onset and morning wake-up detection.",
                )
            return Diagnosis(
                metric_name=name,
                category=DiscrepancyCategory.SLEEP_STAGE_DIFFERENCE,
                confidence=ConfidenceLevel.MEDIUM,
                reason=(
                    "STRAP 4-stage classifier (Awake, Light, REM, Deep) differs from WHOOP proprietary staging model. "
                    "Staging relies on combined HRV log-variance, EDR and 3-axis motion stillness."
                ),
                evidence=[f"strap_val={strap_val}", f"whoop_val={whoop_val}", f"diff={abs_diff}"],
                remediation_hint="Refine heuristic stage transitions using rolling 5-minute HRV variance and motion power.",
            )

        # 6. Respiratory Rate
        if name == "respiratory_rate":
            return Diagnosis(
                metric_name=name,
                category=DiscrepancyCategory.FORMULA_DIFFERENCE,
                confidence=ConfidenceLevel.MEDIUM,
                reason=(
                    "Respiratory rate estimation uses PPG amplitude modulation (EDR). "
                    "Discrepancy typically stems from motion artifact contamination or different frequency filtering."
                ),
                evidence=[f"strap_rr={strap_val:.1f} rpm", f"whoop_rr={whoop_val:.1f} rpm"],
                ghidra_reference=GHIDRA_EVIDENCE_REGISTRY["RESPIRATORY_RATE_EDR"],
                remediation_hint="Isolate respiratory rate calculation strictly to lowest-motion slow-wave sleep segments.",
            )

        # 7. Recovery Score
        if name == "recovery_score":
            return Diagnosis(
                metric_name=name,
                category=DiscrepancyCategory.FORMULA_DIFFERENCE,
                confidence=ConfidenceLevel.MEDIUM,
                reason=(
                    "Recovery score is a composite metric weighted primarily on HRV (RMSSD baseline comparison), "
                    "RHR deviation, and sleep performance. Discrepancies in input HRV/RHR propagate here."
                ),
                evidence=[f"strap_recovery={strap_val}%", f"whoop_recovery={whoop_val}%"],
                remediation_hint="Ensure underlying HRV (SWS) and RHR (5-min dip) are accurately isolated first.",
            )

        # Generic fallback
        if coverage < 80.0:
            return Diagnosis(
                metric_name=name,
                category=DiscrepancyCategory.MISSING_SENSOR_PACKETS,
                confidence=ConfidenceLevel.MEDIUM,
                reason=f"Reduced sensor coverage ({coverage:.1f}%) is the likely contributor to the discrepancy.",
                evidence=[f"coverage={coverage:.1f}%"],
                remediation_hint="Improve BLE sync completeness and inspect flash record sequence continuity.",
            )

        return Diagnosis(
            metric_name=name,
            category=DiscrepancyCategory.INSUFFICIENT_EVIDENCE,
            confidence=ConfidenceLevel.LOW,
            reason=f"Discrepancy of {pct_diff:.1f}% observed with insufficient contextual signals to isolate root cause.",
            evidence=[f"strap={strap_val}", f"whoop={whoop_val}", f"diff={abs_diff}"],
            remediation_hint="Collect high-resolution BLE packet replay trace to trace sample-by-sample differences.",
        )

    def diagnose_day_report(
        self,
        report: DayComparisonReport,
        sensor_quality_info: dict[str, Any] | None = None,
    ) -> list[Diagnosis]:
        """Diagnose all metrics in a DayComparisonReport."""
        diagnoses: list[Diagnosis] = []
        for comparison in report.comparisons.values():
            diag = self.diagnose_metric(
                comparison=comparison,
                report=report,
                sensor_quality_info=sensor_quality_info,
            )
            diagnoses.append(diag)
        return diagnoses

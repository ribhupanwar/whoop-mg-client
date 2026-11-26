"""WHOOP Accuracy Lab, Sensor Validation & BLE Packet Replay Engine."""

from .classifier import (
    GHIDRA_EVIDENCE_REGISTRY,
    ConfidenceLevel,
    Diagnosis,
    DiscrepancyCategory,
    GhidraEvidence,
    RootCauseClassifier,
)
from .comparator import (
    DayComparisonReport,
    MetricComparison,
    WhoopStrapComparator,
    parse_timestamp,
)
from .quality import (
    DiagnosticStatus,
    QualityReport,
    SensorQualityMonitor,
)
from .replay import (
    BlePacketReplayEngine,
    DecodedRecordEvent,
    ReplayStats,
    WireImpairmentConfig,
)
from .report import (
    AccuracyReportGenerator,
    generate_svg_hypnogram,
    generate_svg_metric_bars,
)
from .longitudinal import (
    ErrorStats,
    MetricABComparison,
    PairedObservation,
    compute_error_stats,
    evaluate_metric_ab,
)

__all__ = [
    "AccuracyReportGenerator",
    "BlePacketReplayEngine",
    "ConfidenceLevel",
    "DayComparisonReport",
    "DecodedRecordEvent",
    "Diagnosis",
    "DiagnosticStatus",
    "DiscrepancyCategory",
    "ErrorStats",
    "GHIDRA_EVIDENCE_REGISTRY",
    "GhidraEvidence",
    "MetricABComparison",
    "MetricComparison",
    "PairedObservation",
    "QualityReport",
    "ReplayStats",
    "RootCauseClassifier",
    "SensorQualityMonitor",
    "WhoopStrapComparator",
    "WireImpairmentConfig",
    "compute_error_stats",
    "evaluate_metric_ab",
    "generate_svg_hypnogram",
    "generate_svg_metric_bars",
    "parse_timestamp",
]

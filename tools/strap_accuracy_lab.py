#!/usr/bin/env python3
"""STRAP Accuracy Lab, Sensor Validation & BLE Packet Replay CLI.

Offline-first tool to:
1. Compare STRAP sensor metrics against user-authorized WHOOP export archives.
2. Classify root causes of discrepancies with byte-verified Ghidra evidence.
3. Replay raw BLE packet logs through production decoders with wire impairment simulation.
4. Monitor sensor telemetry quality, packet loss, and RR validity.
5. Generate offline standalone HTML reports with inline SVG charts.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Add project root to path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from whoop.accuracy import (
    AccuracyReportGenerator,
    BlePacketReplayEngine,
    ConfidenceLevel,
    DayComparisonReport,
    Diagnosis,
    DiagnosticStatus,
    DiscrepancyCategory,
    QualityReport,
    RootCauseClassifier,
    SensorQualityMonitor,
    WhoopStrapComparator,
    WireImpairmentConfig,
    DualBandGymComparator,
)
from whoop.records import V18Sample


def cmd_compare(args: argparse.Namespace) -> int:
    """Execute WHOOP vs STRAP multi-metric comparison."""
    comparator = WhoopStrapComparator()

    cycles_path = args.cycles
    sleeps_path = args.sleeps
    workouts_path = args.workouts

    if args.whoop_dir:
        whoop_dir = Path(args.whoop_dir)
        if not cycles_path and (whoop_dir / "physiological_cycles.csv").exists():
            cycles_path = str(whoop_dir / "physiological_cycles.csv")
        if not sleeps_path and (whoop_dir / "sleeps.csv").exists():
            sleeps_path = str(whoop_dir / "sleeps.csv")
        if not workouts_path and (whoop_dir / "workouts.csv").exists():
            workouts_path = str(whoop_dir / "workouts.csv")

    if not cycles_path and not sleeps_path:
        print("Error: Must provide --whoop-dir or at least --cycles/--sleeps", file=sys.stderr)
        return 1

    # Load WHOOP export files
    if cycles_path and os.path.exists(cycles_path):
        with open(cycles_path, "r", encoding="utf-8", errors="replace") as f:
            count = comparator.load_whoop_cycles(f.read())
            print(f"Loaded {count} WHOOP physiological cycles from {cycles_path}")

    if sleeps_path and os.path.exists(sleeps_path):
        with open(sleeps_path, "r", encoding="utf-8", errors="replace") as f:
            count = comparator.load_whoop_sleeps(f.read())
            print(f"Loaded {count} WHOOP sleep records from {sleeps_path}")

    if workouts_path and os.path.exists(workouts_path):
        with open(workouts_path, "r", encoding="utf-8", errors="replace") as f:
            count = comparator.load_whoop_workouts(f.read())
            print(f"Loaded {count} WHOOP workout records from {workouts_path}")

    # Load STRAP sensor records
    strap_samples: list[V18Sample] = []
    if args.strap_csv and os.path.exists(args.strap_csv):
        with open(args.strap_csv, "r", encoding="utf-8", errors="replace") as f:
            strap_samples = comparator.load_strap_samples_csv(f.read())
            print(f"Loaded {len(strap_samples)} STRAP 1 Hz sensor samples from {args.strap_csv}")

    reports = comparator.compare_all()
    if not reports:
        print("No overlapping cycles found between WHOOP and STRAP data.")
        return 0

    classifier = RootCauseClassifier()
    reporter = AccuracyReportGenerator()
    monitor = SensorQualityMonitor()

    quality = monitor.assess_samples(strap_samples) if strap_samples else None

    for report in reports:
        diagnoses = classifier.diagnose_day_report(report)
        md_text = reporter.generate_markdown(report, diagnoses, quality=quality)
        print("\n" + md_text)

        if args.output_html:
            html_content = reporter.generate_html(report, diagnoses, quality=quality)
            with open(args.output_html, "w", encoding="utf-8") as out_f:
                out_f.write(html_content)
            print(f"\nSaved standalone offline HTML report to: {args.output_html}")

        if args.output_md:
            with open(args.output_md, "w", encoding="utf-8") as out_f:
                out_f.write(md_text)
            print(f"Saved Markdown report to: {args.output_md}")

    return 0


def cmd_replay(args: argparse.Namespace) -> int:
    """Execute BLE notification packet replay with simulated impairments."""
    impairments = WireImpairmentConfig(
        mtu_chunk_size=args.mtu,
        drop_rate=args.drop_rate,
        duplicate_rate=args.duplicate_rate,
        corrupt_rate=args.corrupt_rate,
        reorder_depth=args.reorder_depth,
        reconnect_every_n_chunks=args.reconnect_every,
    )
    engine = BlePacketReplayEngine(impairments=impairments)

    if not os.path.exists(args.input):
        print(f"Error: Replay input file not found: {args.input}", file=sys.stderr)
        return 1

    with open(args.input, "r", encoding="utf-8", errors="replace") as f:
        log_content = f.read()

    print(f"Replaying BLE notification chunks from {args.input}...")
    events = list(engine.replay_hex_log(log_content))

    print("\n--- BLE Packet Replay Statistics ---")
    print(f"Chunks fed:               {engine.stats.chunks_fed}")
    print(f"Raw bytes fed:            {engine.stats.raw_bytes_fed}")
    print(f"Frames reassembled:       {engine.stats.frames_reassembled}")
    print(f"V18 samples decoded:      {engine.stats.v18_decoded}")
    print(f"V26 records decoded:      {engine.stats.v26_decoded}")
    print(f"V21 IMU buffers decoded:  {engine.stats.v21_decoded}")
    print(f"Other frames decoded:     {engine.stats.other_frames}")
    print(f"Dropped bytes:            {engine.stats.dropped_bytes}")
    print(f"Bad frames rejected:      {engine.stats.bad_frames}")
    print(f"Injected drops:           {engine.stats.dropped_injected}")
    print(f"Injected corruptions:     {engine.stats.corrupted_injected}")
    print(f"Injected duplicates:      {engine.stats.duplicated_injected}")
    print(f"Simulated reconnects:     {engine.stats.reconnect_events}")

    if args.output:
        records_data = []
        for ev in events:
            rec_dict = {
                "record_type": ev.record_type,
                "timestamp": ev.timestamp,
            }
            if isinstance(ev.data, V18Sample):
                rec_dict["heart_rate"] = ev.data.heart_rate
                rec_dict["rr_intervals_ms"] = ev.data.rr_intervals_ms
                rec_dict["dynamic_accel_g"] = ev.data.dynamic_accel_g
            records_data.append(rec_dict)
        with open(args.output, "w", encoding="utf-8") as out_f:
            json.dump(records_data, out_f, indent=2)
        print(f"Exported {len(records_data)} decoded events to {args.output}")

    return 0


def cmd_monitor(args: argparse.Namespace) -> int:
    """Evaluate sensor telemetry quality from a STRAP sensor CSV."""
    if not os.path.exists(args.input):
        print(f"Error: Sensor input file not found: {args.input}", file=sys.stderr)
        return 1

    comparator = WhoopStrapComparator()
    with open(args.input, "r", encoding="utf-8", errors="replace") as f:
        samples = comparator.load_strap_samples_csv(f.read())

    monitor = SensorQualityMonitor()
    report = monitor.assess_samples(samples, expected_window_seconds=args.expected_seconds)

    print("\n=== STRAP Sensor Data Quality Report ===")
    print(f"Diagnostic Status:        {report.status.value}")
    print(f"Total Samples:            {report.total_samples}")
    print(f"Duration:                 {report.duration_seconds}s")
    print(f"Coverage:                 {report.coverage_pct:.1f}%")
    print(f"Packet Loss Rate:         {report.packet_loss_rate_pct:.1f}%")
    print(f"RR Validity Rate:         {report.rr_validity_rate_pct:.1f}% ({report.rr_valid_count}/{report.rr_total_count})")
    print(f"Max Data Gap:             {report.max_gap_seconds:.1f}s")
    print(f"Gaps > 5s:                {report.gaps_greater_than_5s}")
    print(f"Stillness Ratio:          {report.stillness_ratio_pct:.1f}%")
    print(f"HR Zero (Off-skin):       {report.hr_zero_count}")

    if report.issues:
        print("\nFlagged Issues:")
        for issue in report.issues:
            print(f"  [!] {issue}")
    else:
        print("\n[OK] Telemetry stream is continuous and nominal.")

    return 0


def cmd_gym_compare(args: argparse.Namespace) -> int:
    """Execute controlled dual-band gym workout comparison."""
    if not os.path.exists(args.strap_csv):
        print(f"Error: STRAP CSV not found: {args.strap_csv}", file=sys.stderr)
        return 1
    if not os.path.exists(args.whoop_csv):
        print(f"Error: WHOOP CSV not found: {args.whoop_csv}", file=sys.stderr)
        return 1

    with open(args.strap_csv, "r", encoding="utf-8", errors="replace") as f:
        strap_csv_content = f.read()

    with open(args.whoop_csv, "r", encoding="utf-8", errors="replace") as f:
        whoop_csv_content = f.read()

    comparator = DualBandGymComparator()
    strap_telem = comparator.parse_strap_workout_csv(strap_csv_content)
    whoop_telem = comparator.parse_whoop_workout_stream(
        whoop_csv_content,
        activity_kind=args.activity,
        start_unix=strap_telem.start_unix,
        end_unix=strap_telem.end_unix,
        whoop_strain=args.whoop_strain,
        whoop_kcal=args.whoop_kcal,
    )

    res = comparator.compare(strap_telem, whoop_telem)
    md_report = comparator.generate_markdown_report(res)

    print("\n" + md_report)

    if args.output_md:
        with open(args.output_md, "w", encoding="utf-8") as f:
            f.write(md_report)
        print(f"[OK] Markdown report saved to: {args.output_md}")

    if args.output_json:
        result_dict = {
            "activity_kind": res.activity_kind,
            "duration_seconds": res.duration_seconds,
            "hr_mae": res.hr_mae,
            "hr_rmse": res.hr_rmse,
            "hr_pearson_r": res.hr_pearson_r,
            "optimal_lag_seconds": res.optimal_lag_seconds,
            "strap_mean_hr": res.strap_mean_hr,
            "whoop_mean_hr": res.whoop_mean_hr,
            "mean_hr_delta": res.mean_hr_delta,
            "strap_max_hr": res.strap_max_hr,
            "whoop_max_hr": res.whoop_max_hr,
            "max_hr_delta": res.max_hr_delta,
            "strain_delta": res.strain_delta,
            "is_parity_acceptable": res.is_parity_acceptable,
        }
        with open(args.output_json, "w", encoding="utf-8") as f:
            json.dump(result_dict, f, indent=2)
        print(f"[OK] JSON comparison saved to: {args.output_json}")

    return 0 if res.is_parity_acceptable else 1


def main() -> int:
    parser = argparse.ArgumentParser(
        description="STRAP WHOOP Accuracy Lab, Sensor Validation & BLE Replay Engine"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Subcommand: compare
    p_comp = subparsers.add_parser("compare", help="Compare STRAP metrics against WHOOP export")
    p_comp.add_argument("--whoop-dir", help="Directory containing WHOOP export CSV files")
    p_comp.add_argument("--cycles", help="Path to physiological_cycles.csv")
    p_comp.add_argument("--sleeps", help="Path to sleeps.csv")
    p_comp.add_argument("--workouts", help="Path to workouts.csv")
    p_comp.add_argument("--strap-csv", help="Path to STRAP 1 Hz sensor records CSV")
    p_comp.add_argument("--output-html", help="Path to generate standalone offline HTML report")
    p_comp.add_argument("--output-md", help="Path to generate Markdown summary report")

    # Subcommand: replay
    p_rep = subparsers.add_parser("replay", help="Replay raw BLE packet hex logs with impairments")
    p_rep.add_argument("--input", required=True, help="Path to hex dump or log file")
    p_rep.add_argument("--mtu", type=int, default=244, help="ATT MTU payload chunk size")
    p_rep.add_argument("--drop-rate", type=float, default=0.0, help="Chunk drop rate (0.0 to 1.0)")
    p_rep.add_argument("--corrupt-rate", type=float, default=0.0, help="Chunk corruption rate (0.0 to 1.0)")
    p_rep.add_argument("--duplicate-rate", type=float, default=0.0, help="Chunk duplication rate (0.0 to 1.0)")
    p_rep.add_argument("--reorder-depth", type=int, default=0, help="Chunk reorder depth buffer")
    p_rep.add_argument("--reconnect-every", type=int, default=0, help="Simulate reconnect every N chunks")
    p_rep.add_argument("--output", help="Optional JSON path to save decoded events")

    # Subcommand: monitor
    p_mon = subparsers.add_parser("monitor", help="Assess sensor telemetry quality")
    p_mon.add_argument("--input", required=True, help="Path to STRAP sensor CSV file")
    p_mon.add_argument("--expected-seconds", type=float, help="Expected duration in seconds")

    # Subcommand: gym-compare
    p_gym = subparsers.add_parser("gym-compare", help="Controlled dual-band gym trial comparison")
    p_gym.add_argument("--strap-csv", required=True, help="Path to STRAP workout export CSV")
    p_gym.add_argument("--whoop-csv", required=True, help="Path to WHOOP workout HR stream CSV")
    p_gym.add_argument("--activity", default="Weightlifting", help="Activity name")
    p_gym.add_argument("--whoop-strain", type=float, help="Official WHOOP workout strain")
    p_gym.add_argument("--whoop-kcal", type=float, help="Official WHOOP active calories")
    p_gym.add_argument("--output-md", help="Path to save Markdown comparison report")
    p_gym.add_argument("--output-json", help="Path to save JSON comparison result")

    args = parser.parse_args()

    if args.command == "compare":
        return cmd_compare(args)
    elif args.command == "replay":
        return cmd_replay(args)
    elif args.command == "monitor":
        return cmd_monitor(args)
    elif args.command == "gym-compare":
        return cmd_gym_compare(args)

    return 0


if __name__ == "__main__":
    sys.exit(main())

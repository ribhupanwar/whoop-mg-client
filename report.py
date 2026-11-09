"""Compute every local metric from a capture and render a recovery-ring dashboard.

These are local, published-science estimates - NOT WHOOP's Recovery, Strain or
Sleep scores, which are proprietary cloud algorithms. Anything the data cannot
support is reported as absent with a reason, never guessed.

Usage:
    python report.py session3.jsonl --age 30 --sex male --rhr 55 --sleep-need 8
"""

import argparse
import html
import json
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from decode import load_samples
from whoop.health import (
    Baseline,
    RecoveryResult,
    SleepPeriod,
    detect_sleep,
    recovery_score,
    strain_label,
    strain_score,
    total_sleep_hours,
)
from whoop.metrics import (
    HrvResult,
    age_predicted_max_hr,
    resting_heart_rate,
    resting_hrv,
    trimp,
)

DISCLAIMER = (
    "Local estimates from published physiology (Malik 1996 HRV, Banister TRIMP, "
    "Karvonen HR reserve). Not WHOOP scores - WHOOP's recovery, strain and sleep "
    "staging are proprietary and are not reproduced here."
)


@dataclass
class Report:
    source: str
    samples: int
    on_wrist: int
    start_utc: str
    end_utc: str
    hrv: HrvResult
    hrv_window_s: int
    rhr_measured: float | None
    rhr_used: float | None
    rhr_source: str
    sleep_periods: list[SleepPeriod]
    sleep_hours: float
    trimp_value: float | None
    strain: float | None
    recovery: RecoveryResult


def build_report(
    samples: list,
    source: str,
    age: int | None,
    sex: str,
    max_hr: float | None,
    rhr_override: float | None,
    sleep_need: float | None,
    baseline: Baseline | None,
) -> Report:
    ordered = sorted(samples, key=lambda s: s.unix)
    wearing = [s for s in ordered if s.wearing]
    hrv_result, hrv_window_s = resting_hrv(ordered)
    measured = resting_heart_rate(ordered)

    if measured is not None:
        rhr_used, rhr_source = measured, "measured from a quiet window"
    elif rhr_override is not None:
        rhr_used, rhr_source = rhr_override, "user-supplied (not measured)"
    else:
        rhr_used, rhr_source = None, "unavailable - no quiet window and no --rhr"

    effective_max = max_hr if max_hr is not None else (
        age_predicted_max_hr(age) if age else None
    )
    trimp_value = None
    if rhr_used is not None and effective_max is not None and effective_max > rhr_used:
        trimp_value = trimp(ordered, effective_max, rhr_used, sex=sex)

    periods = detect_sleep(ordered)
    sleep_hours = total_sleep_hours(periods)
    recovery = recovery_score(
        hrv_result.ln_rmssd,
        measured,
        sleep_hours if periods else None,
        sleep_need,
        baseline,
    )

    return Report(
        source=source,
        samples=len(ordered),
        on_wrist=len(wearing),
        start_utc=(
            datetime.fromtimestamp(ordered[0].unix, timezone.utc).isoformat()
            if ordered else "n/a"
        ),
        end_utc=(
            datetime.fromtimestamp(ordered[-1].unix, timezone.utc).isoformat()
            if ordered else "n/a"
        ),
        hrv=hrv_result,
        hrv_window_s=hrv_window_s,
        rhr_measured=measured,
        rhr_used=rhr_used,
        rhr_source=rhr_source,
        sleep_periods=periods,
        sleep_hours=sleep_hours,
        trimp_value=trimp_value,
        strain=strain_score(trimp_value),
        recovery=recovery,
    )


def _fmt(value: float | None, suffix: str = "", places: int = 1) -> str:
    return "—" if value is None else f"{value:.{places}f}{suffix}"


DEFAULT_BASELINE = "baseline.json"


def load_daily(path: Path) -> dict[str, dict]:
    """Day-keyed readings, so re-running a capture updates rather than duplicates."""
    if not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {row["date"]: row for row in raw.get("days", [])}


def record_day(path: Path, date: str, ln_rmssd: float, rhr: float) -> int:
    days = load_daily(path)
    days[date] = {"date": date, "ln_rmssd": ln_rmssd, "rhr": rhr}
    ordered = [days[key] for key in sorted(days)]
    path.write_text(json.dumps({"days": ordered}, indent=2) + "\n", encoding="utf-8")
    return len(ordered)


def baseline_from_file(path: Path) -> Baseline | None:
    days = load_daily(path)
    rows = [days[key] for key in sorted(days)]
    return Baseline.from_daily(
        [r["ln_rmssd"] for r in rows], [r["rhr"] for r in rows]
    )


def print_report(report: Report) -> None:
    print(f"\n=== Local health report: {report.source} ===")
    print(f"  {report.samples} samples, {report.on_wrist} on-wrist")
    print(f"  {report.start_utc}  ->  {report.end_utc}")

    print(f"\n  Resting HR : {_fmt(report.rhr_measured, ' bpm')}  ({report.rhr_source})")
    print(
        f"  HRV        : RMSSD {_fmt(report.hrv.rmssd_ms, ' ms')},"
        f" SDNN {_fmt(report.hrv.sdnn_ms, ' ms')},"
        f" pNN50 {_fmt(report.hrv.pnn50_pct, '%')}"
        f"  [{report.hrv.nn_beats}/{report.hrv.beats} NN beats]"
    )
    if report.hrv_window_s:
        print(f"               from the longest quiet run: {report.hrv_window_s} s")
    else:
        print("               no quiet run of at least 60 s; HRV at rest needs stillness")
    if report.sleep_periods:
        print(
            f"  Sleep      : {_fmt(report.sleep_hours, ' h')} across"
            f" {len(report.sleep_periods)} period(s)"
        )
    else:
        print("  Sleep      : —  (no sleep period detected; needs an overnight capture)")
    for period in report.sleep_periods:
        start = datetime.fromtimestamp(period.start_unix, timezone.utc).strftime("%H:%M")
        print(
            f"               {start}  {period.hours:.2f} h"
            f"  continuity {period.quiet_fraction * 100:.0f}%"
            f"  mean HR {_fmt(period.mean_hr, ' bpm')}"
        )
    print(
        f"  Strain     : {_fmt(report.strain)} / 21  ({strain_label(report.strain)})"
        f"  TRIMP {_fmt(report.trimp_value)}"
    )
    if report.recovery.score is None:
        print(f"  Recovery   : unavailable - {report.recovery.reason}")
    else:
        print(
            f"  Recovery   : {report.recovery.score:.0f} / 100"
            f"  [{report.recovery.band}]"
            f"  HRV {report.recovery.hrv_component}"
            f"  RHR {report.recovery.rhr_component}"
            f"  sleep {report.recovery.sleep_component}"
        )
    print(f"\n  {DISCLAIMER}")


RING_RADIUS = 85
RING_CIRCUMFERENCE = 2 * math.pi * RING_RADIUS
BAND_COLORS = {
    "green": "#3fb950",
    "yellow": "#d29922",
    "red": "#f85149",
    "unavailable": "#4a5261",
}


def _card(title: str, value: str, detail: str) -> str:
    return (
        f'<div class="card"><div class="card-title">{html.escape(title)}</div>'
        f'<div class="card-value">{html.escape(value)}</div>'
        f'<div class="card-detail">{html.escape(detail)}</div></div>'
    )


def render_html(report: Report) -> str:
    recovery = report.recovery
    color = BAND_COLORS[recovery.band]
    score_text = "—" if recovery.score is None else f"{recovery.score:.0f}"
    fraction = 0.0 if recovery.score is None else recovery.score / 100.0
    offset = RING_CIRCUMFERENCE * (1.0 - fraction)
    ring_detail = recovery.reason if recovery.score is None else (
        f"HRV {recovery.hrv_component} · RHR {recovery.rhr_component}"
        + (f" · sleep {recovery.sleep_component}" if recovery.sleep_component is not None else "")
    )

    cards = [
        _card(
            "Resting HR",
            _fmt(report.rhr_measured, " bpm"),
            report.rhr_source if report.rhr_measured is None else "lowest sustained quiet-window rate",
        ),
        _card(
            "HRV · RMSSD",
            _fmt(report.hrv.rmssd_ms, " ms"),
            f"{report.hrv.nn_beats}/{report.hrv.beats} NN beats"
            + (
                f" · {report.hrv_window_s} s quiet run"
                if report.hrv_window_s
                else " · needs a rest/sleep window"
            ),
        ),
        _card(
            "Sleep",
            _fmt(report.sleep_hours, " h") if report.sleep_periods else "—",
            f"{len(report.sleep_periods)} period(s)"
            + ("" if report.sleep_periods else " · needs an overnight capture"),
        ),
        _card(
            "Strain",
            _fmt(report.strain) + " / 21",
            f"{strain_label(report.strain)} · TRIMP {_fmt(report.trimp_value)}",
        ),
    ]

    sleep_rows = "".join(
        "<tr>"
        f"<td>{datetime.fromtimestamp(p.start_unix, timezone.utc).strftime('%Y-%m-%d %H:%M')}</td>"
        f"<td>{p.hours:.2f} h</td>"
        f"<td>{p.quiet_fraction * 100:.0f}%</td>"
        f"<td>{_fmt(p.mean_hr)}</td>"
        "</tr>"
        for p in report.sleep_periods
    )
    sleep_table = (
        "<table><thead><tr><th>Start (UTC)</th><th>Duration</th>"
        "<th>Continuity</th><th>Mean HR</th></tr></thead>"
        f"<tbody>{sleep_rows}</tbody></table>"
        if sleep_rows else ""
    )

    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>WHOOP MG · local health report</title>
<style>
:root{{color-scheme:dark}}
*{{box-sizing:border-box}}
body{{margin:0;background:#0d1117;color:#e6edf3;
font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;padding:28px}}
.wrap{{max-width:880px;margin:0 auto}}
h1{{font-size:20px;margin:0 0 4px}}
.sub{{color:#8b949e;font-size:13px;margin-bottom:22px}}
.banner{{background:#161b22;border:1px solid #30363d;border-left:3px solid #d29922;
padding:10px 14px;border-radius:6px;font-size:12.5px;color:#8b949e;margin-bottom:24px}}
.hero{{display:flex;gap:28px;align-items:center;background:#161b22;
border:1px solid #30363d;border-radius:12px;padding:24px;margin-bottom:20px;flex-wrap:wrap}}
.ring{{position:relative;width:200px;height:200px;flex:0 0 auto}}
.ring svg{{display:block}}
.ring-num{{position:absolute;inset:0;display:flex;flex-direction:column;
align-items:center;justify-content:center}}
.ring-num b{{font-size:46px;font-weight:650;line-height:1}}
.ring-num span{{font-size:11px;letter-spacing:.14em;color:#8b949e;margin-top:6px}}
.hero-meta{{flex:1;min-width:220px}}
.band{{display:inline-block;padding:3px 12px;border-radius:999px;font-size:12px;
font-weight:600;background:{color}22;color:{color};border:1px solid {color}55}}
.hero-meta p{{color:#8b949e;font-size:13px;margin:10px 0 0}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px}}
.card{{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:16px}}
.card-title{{font-size:11px;letter-spacing:.1em;color:#8b949e;text-transform:uppercase}}
.card-value{{font-size:26px;font-weight:600;margin:8px 0 4px}}
.card-detail{{font-size:12px;color:#8b949e}}
table{{width:100%;border-collapse:collapse;margin-top:18px;font-size:13px}}
th,td{{text-align:left;padding:8px 10px;border-bottom:1px solid #21262d}}
th{{color:#8b949e;font-weight:500;font-size:11px;text-transform:uppercase;letter-spacing:.08em}}
footer{{margin-top:26px;color:#6e7681;font-size:11.5px;border-top:1px solid #21262d;padding-top:14px}}
</style></head><body><div class="wrap">
<h1>WHOOP MG &middot; local health report</h1>
<div class="sub">{html.escape(report.source)} &middot; {report.samples} samples,
{report.on_wrist} on-wrist &middot; {html.escape(report.start_utc)} &rarr; {html.escape(report.end_utc)}</div>
<div class="banner">{html.escape(DISCLAIMER)}</div>
<div class="hero">
<div class="ring"><svg viewBox="0 0 200 200" width="200" height="200" role="img"
aria-label="Recovery {score_text} out of 100">
<circle cx="100" cy="100" r="{RING_RADIUS}" fill="none" stroke="#21262d" stroke-width="16"/>
<circle cx="100" cy="100" r="{RING_RADIUS}" fill="none" stroke="{color}" stroke-width="16"
stroke-linecap="round" stroke-dasharray="{RING_CIRCUMFERENCE:.2f}"
stroke-dashoffset="{offset:.2f}" transform="rotate(-90 100 100)"/>
</svg><div class="ring-num"><b>{score_text}</b><span>RECOVERY</span></div></div>
<div class="hero-meta"><span class="band">{recovery.band.upper()}</span>
<p>{html.escape(ring_detail or "")}</p>
<p>Recovery is baseline-relative. It stays unavailable until at least 7 days of
your own HRV and resting-HR history exist, because a recovery number without a
personal baseline is meaningless.</p></div></div>
<div class="grid">{''.join(cards)}</div>
{sleep_table}
<footer>Sleep reports duration and continuity only. Light/deep/REM staging is not
implemented: it requires validated HRV features and a trained model, and guessing
it would fabricate medical-looking output. The band's own sleep-state byte is a
wake/sleep envelope with an unverified value mapping, so it never drives the
sleep decision.</footer>
</div></body></html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", nargs="?", default="session3.jsonl")
    parser.add_argument("--age", type=int)
    parser.add_argument("--sex", choices=["male", "female"], default="male")
    parser.add_argument("--max-hr", type=float, help="measured max HR; overrides the age estimate")
    parser.add_argument("--rhr", type=float, help="resting HR to use when none can be measured")
    parser.add_argument("--sleep-need", type=float, default=8.0)
    parser.add_argument(
        "--baseline", default=DEFAULT_BASELINE,
        help="day-keyed JSON history; read to score recovery",
    )
    parser.add_argument(
        "--record", action="store_true",
        help="append this capture's resting HRV and RHR to the baseline file",
    )
    parser.add_argument("--out", default="dashboard.html")
    args = parser.parse_args()

    path = Path(args.capture)
    if not path.exists():
        print(f"Capture not found: {path}")
        return 1
    samples = load_samples(path)
    if not samples:
        print("No decodable v18 records found.")
        return 1

    history = Path(args.baseline)
    if args.record:
        result, window_s = resting_hrv(sorted(samples, key=lambda s: s.unix))
        measured = resting_heart_rate(samples)
        if result.ln_rmssd is None or measured is None:
            print(
                "Not recorded: this capture has no quiet run yielding both HRV "
                "and resting HR. A partial day would skew the baseline."
            )
        else:
            date = datetime.fromtimestamp(
                max(s.unix for s in samples), timezone.utc
            ).date().isoformat()
            count = record_day(history, date, result.ln_rmssd, measured)
            print(
                f"  Recorded {date}: lnRMSSD {result.ln_rmssd:.3f},"
                f" RHR {measured:.1f} bpm from a {window_s} s quiet run"
                f"  ({count}/7 days)"
            )

    report = build_report(
        samples, str(path), args.age, args.sex, args.max_hr,
        args.rhr, args.sleep_need, baseline_from_file(history),
    )
    print_report(report)
    Path(args.out).write_text(render_html(report), encoding="utf-8")
    print(f"\n  Dashboard -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
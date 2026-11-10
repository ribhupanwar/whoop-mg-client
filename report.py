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
import statistics
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from decode import load_samples
from whoop.activity import ActivitySession, detect_activities
from whoop.health import (
    Baseline,
    RecoveryResult,
    RespRate,
    SleepCoach,
    SleepPeriod,
    Spo2Candidate,
    StressResult,
    clock_label,
    detect_sleep,
    recovery_score,
    resp_rate_from_rr,
    sleep_coach,
    spo2_candidate_summary,
    strain_label,
    strain_score,
    stress_score,
    total_sleep_hours,
)
from whoop.metrics import (
    HrvResult,
    age_predicted_max_hr,
    resting_heart_rate,
    resting_hrv,
    trimp,
)
from whoop.sleep_analysis import SleepAnalysis, analyze_sleep, sleep_consistency

DISCLAIMER = (
    "Local estimates from published physiology (Malik 1996 HRV, Banister TRIMP, "
    "Karvonen HR reserve, RSA respiration). Not WHOOP scores - WHOOP's recovery, "
    "strain and sleep staging are proprietary and are not reproduced here. The "
    "SpO2 candidate comes from the band's own byte and is not a clinical reading."
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
    stress: StressResult
    coach: SleepCoach
    activities: list[ActivitySession]
    sleep_analysis: SleepAnalysis | None
    resp_rate: RespRate
    spo2: Spo2Candidate


def build_report(
    samples: list,
    source: str,
    age: int | None,
    sex: str,
    max_hr: float | None,
    rhr_override: float | None,
    sleep_need: float | None,
    baseline: Baseline | None,
    stress_baseline: Baseline | None = None,
    wake_min: int | None = None,
    tomorrow: str = "easy",
    sleep_history: list[float] | None = None,
    sleep_nights: list[tuple[int, int]] | None = None,
    sleep_baseline: Baseline | None = None,
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
    # A sleep capture's longest quiet run is sleep, and sleep lnRMSSD is not
    # comparable to an awake-quiet norm. Score stress only on awake captures.
    stress = (
        StressResult(None, "sleep capture - stress needs an awake-quiet window")
        if periods
        else stress_score(hrv_result.ln_rmssd, stress_baseline)
    )
    coach = sleep_coach(
        sleep_history or [],
        wake_min,
        base_need_h=sleep_need if sleep_need else 8.0,
        tomorrow=tomorrow,
    )
    activities = detect_activities(ordered)
    analysis = (
        analyze_sleep(ordered, periods, coach.need_h, sleep_nights or [], sleep_baseline)
        if periods else None
    )
    resp_rate = resp_rate_from_rr(ordered)
    spo2 = spo2_candidate_summary(ordered)

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
        stress=stress,
        coach=coach,
        activities=activities,
        sleep_analysis=analysis,
        resp_rate=resp_rate,
        spo2=spo2,
    )


def _fmt(value: float | None, suffix: str = "", places: int = 1) -> str:
    return "—" if value is None else f"{value:.{places}f}{suffix}"


DEFAULT_BASELINE = "baseline.json"
CAPTURE_STATES = frozenset({"awake", "sleep"})


def load_daily(path: Path) -> dict[str, dict]:
    """Readings keyed by date and capture state, so re-running one updates it.

    Awake and sleep lnRMSSD are different populations - sleep runs higher - so
    they must not share a key: an overnight recording would otherwise overwrite
    the daytime reading the stress baseline is built from.
    """
    if not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {f"{row['date']}|{row['state']}": row for row in raw.get("days", [])}


def record_day(
    path: Path,
    date: str,
    ln_rmssd: float,
    rhr: float,
    state: str = "awake",
    sleep_h: float | None = None,
    sleep_start: int | None = None,
    sleep_end: int | None = None,
    analysis: SleepAnalysis | None = None,
    debt_h: float | None = None,
) -> int:
    """Store one capture state's reading and return how many days that state has.

    For a sleep night, `analysis` and `debt_h` persist the per-night components
    so weekly trends can be rebuilt later without the original capture. The
    composite (performance, rolling consistency) is recomputed by
    sleep_trends_from_file, not stored, so there is one source of truth.
    """
    if state not in CAPTURE_STATES:
        raise ValueError(f"state must be one of {sorted(CAPTURE_STATES)}")
    days = load_daily(path)
    row = {"date": date, "state": state, "ln_rmssd": ln_rmssd, "rhr": rhr}
    if sleep_h is not None:
        row["sleep_h"] = round(sleep_h, 3)
    if sleep_start is not None:
        row["sleep_start"] = sleep_start
    if sleep_end is not None:
        row["sleep_end"] = sleep_end
    if analysis is not None:
        row["need_h"] = round(analysis.need_h, 3)
        row["efficiency_pct"] = analysis.efficiency_pct
        row["wake_events"] = analysis.wake_events
        if analysis.stress.high_pct is not None:
            row["stress_high_pct"] = analysis.stress.high_pct
            row["stress_medium_pct"] = analysis.stress.medium_pct
            row["stress_low_pct"] = analysis.stress.low_pct
    if debt_h is not None:
        row["debt_h"] = round(debt_h, 3)
    days[f"{date}|{state}"] = row
    ordered = [days[key] for key in sorted(days)]
    path.write_text(json.dumps({"days": ordered}, indent=2) + "\n", encoding="utf-8")
    return sum(1 for row in ordered if row["state"] == state)


def baseline_from_file(path: Path) -> Baseline | None:
    days = load_daily(path)
    rows = [days[key] for key in sorted(days)]
    return Baseline.from_daily(
        [r["ln_rmssd"] for r in rows], [r["rhr"] for r in rows]
    )


def stress_baseline_from_file(path: Path) -> Baseline | None:
    """Awake-quiet days only, because stress is scored against an awake norm."""
    days = load_daily(path)
    rows = [days[key] for key in sorted(days) if days[key]["state"] == "awake"]
    return Baseline.from_daily(
        [r["ln_rmssd"] for r in rows], [r["rhr"] for r in rows]
    )


def sleep_history_from_file(path: Path) -> list[float]:
    """Night sleep durations in date order, feeding the sleep-debt balance."""
    days = load_daily(path)
    return [
        days[key]["sleep_h"]
        for key in sorted(days)
        if days[key]["state"] == "sleep" and days[key].get("sleep_h") is not None
    ]


def sleep_nights_from_file(path: Path) -> list[tuple[int, int]]:
    """(bed, wake) unix pairs in date order, feeding the consistency rule."""
    days = load_daily(path)
    return [
        (days[key]["sleep_start"], days[key]["sleep_end"])
        for key in sorted(days)
        if days[key]["state"] == "sleep"
        and days[key].get("sleep_start") is not None
        and days[key].get("sleep_end") is not None
    ]


def sleep_baseline_from_file(path: Path) -> Baseline | None:
    """Sleep-state days only: sleep stress is scored against the sleep norm."""
    days = load_daily(path)
    rows = [days[key] for key in sorted(days) if days[key]["state"] == "sleep"]
    return Baseline.from_daily(
        [r["ln_rmssd"] for r in rows], [r["rhr"] for r in rows]
    )


def sleep_trends_from_file(path: Path) -> list[dict]:
    """Per-night rows for the weekly sleep charts, in date order.

    Performance and consistency are recomputed here (consistency rolls over
    the nights recorded up to each date) so the charts reuse the exact rules
    in analyze_sleep / sleep_consistency rather than a stored guess. Any
    component a night lacks stays None and renders as a gap.
    """
    days = load_daily(path)
    rows = [days[key] for key in sorted(days) if days[key]["state"] == "sleep"]
    nights: list[tuple[int, int]] = []
    trends: list[dict] = []
    for row in rows:
        bed, wake = row.get("sleep_start"), row.get("sleep_end")
        has_span = bed is not None and wake is not None and wake > bed
        if has_span:
            nights.append((bed, wake))
        consistency_pct, _ = sleep_consistency(nights)
        sleep_h, need_h = row.get("sleep_h"), row.get("need_h")
        hours_pct = (
            round(min(100.0, 100.0 * sleep_h / need_h), 1)
            if sleep_h is not None and need_h else None
        )
        high = row.get("stress_high_pct")
        components = [
            c for c in (
                hours_pct, row.get("efficiency_pct"), consistency_pct,
                None if high is None else 100.0 - high,
            ) if c is not None
        ]
        trends.append({
            "date": row["date"],
            "sleep_h": sleep_h,
            "need_h": need_h,
            "hours_vs_needed_pct": hours_pct,
            "efficiency_pct": row.get("efficiency_pct"),
            "wake_events": row.get("wake_events"),
            "bed_unix": bed,
            "wake_unix": wake,
            "time_in_bed_h": round((wake - bed) / 3600.0, 3) if has_span else None,
            "consistency_pct": consistency_pct,
            "debt_h": row.get("debt_h"),
            "stress_high_pct": high,
            "stress_medium_pct": row.get("stress_medium_pct"),
            "stress_low_pct": row.get("stress_low_pct"),
            "performance_pct": round(statistics.mean(components), 1) if components else None,
        })
    return trends


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
    resp = report.resp_rate
    if resp.breaths_per_min is None:
        print(f"  Resp rate  : —  ({resp.reason})")
    else:
        print(
            f"  Resp rate  : {resp.breaths_per_min:.1f} breaths/min"
            f"  (RSA estimate from R-R, {resp.windows} window(s), {resp.beats} beats)"
        )
    spo2 = report.spo2
    if spo2.pct is None:
        print(f"  SpO2 cand. : —  ({spo2.reason})")
    else:
        extras = []
        if spo2.saturated:
            extras.append(f"{spo2.saturated} saturated")
        if spo2.diagnostic:
            extras.append(f"{spo2.diagnostic} diagnostic")
        suffix = f", {', '.join(extras)}" if extras else ""
        print(
            f"  SpO2 cand. : {spo2.pct:.1f} %"
            f"  (band candidate @82, {spo2.readings} reading(s){suffix}"
            " - UNVALIDATED, not a clinical SpO2)"
        )
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
    analysis = report.sleep_analysis
    if analysis is not None:
        print(
            f"  Sleep perf : {_fmt(analysis.performance_pct, '%')}  (local composite)"
            f"  hours/need {analysis.hours_vs_needed_pct:.0f}%"
            f"  efficiency {analysis.efficiency_pct:.0f}%"
            f"  wake events {analysis.wake_events}"
        )
        consistency = (
            f"{analysis.consistency_pct:.0f}% over {analysis.consistency_nights} nights"
            if analysis.consistency_pct is not None
            else "needs 2+ recorded nights"
        )
        stress = (
            f"high {analysis.stress.high_pct:.0f}%"
            f" / medium {analysis.stress.medium_pct:.0f}%"
            f" / low {analysis.stress.low_pct:.0f}%"
            if analysis.stress.high_pct is not None
            else analysis.stress.reason
        )
        print(f"               consistency {consistency}  ·  sleep stress {stress}")
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
    if report.stress.index is None:
        print(f"  Stress     : unavailable - {report.stress.reason}")
    else:
        print(
            f"  Stress     : {report.stress.index:.2f} / 3  [{report.stress.band}]"
            "  SD of lnRMSSD below your awake-quiet norm"
        )
    coach = report.coach
    if coach.bedtime_min is None:
        print(f"  Sleep coach: unavailable - {coach.reason}")
    else:
        debt = (
            f"debt {coach.debt_h:.2f} h over {coach.nights} nights"
            if coach.debt_h is not None
            else "debt unknown - no nights recorded yet"
        )
        print(
            f"  Sleep coach: bed {clock_label(coach.bedtime_min)} ->"
            f" wake {clock_label(coach.wake_min)},"
            f" {coach.time_in_bed_h:.2f} h in bed for {coach.need_h:.2f} h need"
            f"  ({debt})"
        )
    if report.activities:
        print(
            f"  Activities : {len(report.activities)} session(s) auto-detected"
            "  (gait + steps + HR, no start tap)"
        )
    else:
        print(
            "  Activities : —  (no 10-min run/walk/workout session in this capture)"
        )
    for session in report.activities:
        start = datetime.fromtimestamp(session.start_unix, timezone.utc).strftime("%H:%M")
        print(
            f"               {start}  {session.kind}  {session.minutes:.1f} min"
            f"  {session.steps} steps"
            f"  mean HR {_fmt(session.mean_hr, ' bpm')}"
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


def _pct_bar(label: str, pct: float | None, detail: str) -> str:
    width = 0.0 if pct is None else max(0.0, min(100.0, pct))
    value = "—" if pct is None else f"{pct:.0f}%"
    return (
        f'<div class="srow"><div class="srow-top"><span>{html.escape(label)}</span>'
        f'<b>{value}</b></div>'
        f'<div class="strack"><i style="width:{width:.1f}%"></i></div>'
        f'<div class="sdetail">{html.escape(detail)}</div></div>'
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

    coach = report.coach
    if coach.bedtime_min is None:
        coach_value, coach_detail = "—", coach.reason or ""
    else:
        coach_value = f"{clock_label(coach.bedtime_min)} → {clock_label(coach.wake_min)}"
        coach_detail = (
            f"{coach.time_in_bed_h:.2f} h in bed · need {coach.need_h:.2f} h · "
            + (
                f"debt {coach.debt_h:.2f} h over {coach.nights} nights"
                if coach.debt_h is not None
                else "debt unknown until nights are recorded"
            )
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
            "Respiratory rate",
            _fmt(report.resp_rate.breaths_per_min, " /min"),
            (
                f"RSA estimate from R-R · {report.resp_rate.windows} window(s)"
                f" · {report.resp_rate.beats} beats"
                if report.resp_rate.available
                else report.resp_rate.reason or ""
            ),
        ),
        _card(
            "SpO2 candidate",
            "—" if report.spo2.pct is None else f"{report.spo2.pct:.1f} %",
            (
                f"band candidate @82 · {report.spo2.readings} reading(s)"
                " · unvalidated, not clinical"
                if report.spo2.available
                else report.spo2.reason or ""
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
        _card(
            "Stress",
            _fmt(report.stress.index, places=2) + " / 3",
            (
                f"{report.stress.band} · lnRMSSD vs your awake-quiet norm"
                if report.stress.index is not None
                else report.stress.reason
            ),
        ),
        _card("Sleep coach", coach_value, coach_detail),
        _card(
            "Activities",
            f"{len(report.activities)} session(s)" if report.activities else "—",
            "auto-detected · gait + steps + HR"
            if report.activities
            else "no 10-min run/walk/workout in this capture",
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

    activity_rows = "".join(
        "<tr>"
        f"<td>{datetime.fromtimestamp(a.start_unix, timezone.utc).strftime('%Y-%m-%d %H:%M')}</td>"
        f"<td>{html.escape(a.kind)}</td>"
        f"<td>{a.minutes:.1f} min</td>"
        f"<td>{a.steps}</td>"
        f"<td>{_fmt(a.mean_hr)}</td>"
        "</tr>"
        for a in report.activities
    )
    activity_table = (
        "<table><thead><tr><th>Start (UTC)</th><th>Activity</th><th>Duration</th>"
        "<th>Steps</th><th>Mean HR</th></tr></thead>"
        f"<tbody>{activity_rows}</tbody></table>"
        if activity_rows else ""
    )

    analysis = report.sleep_analysis
    analysis_html = ""
    if analysis is not None:
        low_stress = (
            None if analysis.stress.high_pct is None else 100.0 - analysis.stress.high_pct
        )
        analysis_html = (
            '<div class="analysis"><div class="card-title">Sleep analysis · '
            f'local composite {_fmt(analysis.performance_pct, "%")}</div>'
            + _pct_bar(
                "Hours vs. needed", analysis.hours_vs_needed_pct,
                f"{analysis.hours:.2f} h of {analysis.need_h:.2f} h need",
            )
            + _pct_bar(
                "Sleep consistency", analysis.consistency_pct,
                f"±60 min of median bed/wake · {analysis.consistency_nights} nights"
                if analysis.consistency_pct is not None
                else "needs 2+ recorded nights",
            )
            + _pct_bar(
                "Sleep efficiency", analysis.efficiency_pct,
                f"quiet vs movement · {analysis.wake_events} wake events",
            )
            + _pct_bar(
                "Low sleep stress", low_stress,
                "vs your sleep norm"
                if low_stress is not None else analysis.stress.reason or "",
            )
            + "</div>"
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
.analysis{{background:#161b22;border:1px solid #30363d;border-radius:10px;
padding:16px;margin-top:14px}}
.srow{{margin-top:12px}}
.srow-top{{display:flex;justify-content:space-between;font-size:13px}}
.srow-top span{{color:#8b949e}}
.strack{{height:6px;background:#21262d;border-radius:3px;margin:6px 0 4px;overflow:hidden}}
.strack i{{display:block;height:100%;background:#7b8fa8;border-radius:3px}}
.sdetail{{font-size:11.5px;color:#6e7681}}
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
{analysis_html}
{sleep_table}
{activity_table}
<footer>Sleep reports duration and continuity only. Light/deep/REM staging is not
implemented: it requires validated HRV features and a trained model, and guessing
it would fabricate medical-looking output. The band's own sleep-state byte is a
wake/sleep envelope with an unverified value mapping, so it never drives the
sleep decision. Respiratory rate is an RSA estimate from R-R timing, not a
chest-band measurement. SpO2 is only the band's unvalidated @82 candidate and is
never a clinical reading. Activities are auto-detected from the band's gait
readout, the step counter and sustained heart-rate elevation; sessions under ten
minutes are not logged, and the gait enum is not vendor-verified.</footer>
</div></body></html>
"""


def _wake_minutes(text: str) -> int:
    try:
        hours, minutes = (int(part) for part in text.split(":"))
    except ValueError:
        raise argparse.ArgumentTypeError("wake time must be HH:MM") from None
    if not (0 <= hours < 24 and 0 <= minutes < 60):
        raise argparse.ArgumentTypeError("wake time must be HH:MM")
    return hours * 60 + minutes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", nargs="?", default="session3.jsonl")
    parser.add_argument("--age", type=int)
    parser.add_argument("--sex", choices=["male", "female"], default="male")
    parser.add_argument("--max-hr", type=float, help="measured max HR; overrides the age estimate")
    parser.add_argument("--rhr", type=float, help="resting HR to use when none can be measured")
    parser.add_argument("--sleep-need", type=float, default=8.0)
    parser.add_argument(
        "--wake", type=_wake_minutes,
        help="local wake time HH:MM; enables the sleep-coach suggested bedtime",
    )
    parser.add_argument(
        "--tomorrow", choices=["hard", "easy", "rest"], default="easy",
        help="tomorrow's plan; adds a coaching sleep allowance on top of need",
    )
    parser.add_argument(
        "--baseline", default=DEFAULT_BASELINE,
        help="JSON history keyed by date and capture state; scores recovery and stress",
    )
    parser.add_argument(
        "--record", action="store_true",
        help="append this capture's resting HRV and RHR to the baseline file, "
             "tagged awake or sleep by whether a sleep period was detected",
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
            periods = detect_sleep(samples)
            state = "sleep" if periods else "awake"
            sleep_h = total_sleep_hours(periods) if periods else None
            analysis = None
            debt_h = None
            if periods:
                bed = min(p.start_unix for p in periods)
                wake = max(p.end_unix for p in periods)
                coach = sleep_coach(
                    sleep_history_from_file(history), args.wake,
                    base_need_h=args.sleep_need, tomorrow=args.tomorrow,
                )
                debt_h = coach.debt_h
                analysis = analyze_sleep(
                    sorted(samples, key=lambda s: s.unix), periods, coach.need_h,
                    sleep_nights_from_file(history) + [(bed, wake)],
                    sleep_baseline_from_file(history),
                )
            count = record_day(
                history, date, result.ln_rmssd, measured, state, sleep_h=sleep_h,
                sleep_start=min(p.start_unix for p in periods) if periods else None,
                sleep_end=max(p.end_unix for p in periods) if periods else None,
                analysis=analysis, debt_h=debt_h,
            )
            print(
                f"  Recorded {date} [{state}]: lnRMSSD {result.ln_rmssd:.3f},"
                f" RHR {measured:.1f} bpm from a {window_s} s quiet run"
                + (f", sleep {sleep_h:.2f} h" if sleep_h is not None else "")
                + f"  ({count}/7 {state} days)"
            )

    report = build_report(
        samples, str(path), args.age, args.sex, args.max_hr,
        args.rhr, args.sleep_need, baseline_from_file(history),
        stress_baseline=stress_baseline_from_file(history),
        wake_min=args.wake,
        tomorrow=args.tomorrow,
        sleep_history=sleep_history_from_file(history),
        sleep_nights=sleep_nights_from_file(history),
        sleep_baseline=sleep_baseline_from_file(history),
    )
    print_report(report)
    Path(args.out).write_text(render_html(report), encoding="utf-8")
    print(f"\n  Dashboard -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
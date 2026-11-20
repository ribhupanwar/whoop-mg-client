"""Standalone Offline HTML & Markdown Report Generator.

Produces self-contained offline reports with embedded SVG charts,
discrepancy analysis tables, Ghidra reverse-engineering citations,
and sensor quality telemetry. Zero external network/CDN dependencies.
"""

from __future__ import annotations

import html
import math
from dataclasses import dataclass
from typing import Sequence

from .classifier import Diagnosis, DiscrepancyCategory, GhidraEvidence
from .comparator import DayComparisonReport, MetricComparison
from .quality import QualityReport


def _badge_color_for_category(category: DiscrepancyCategory) -> tuple[str, str]:
    """Returns (background_hex, text_hex) for a diagnostic category."""
    mapping = {
        DiscrepancyCategory.FORMULA_DIFFERENCE: ("#ede9fe", "#5b21b6"),
        DiscrepancyCategory.DIFFERENT_MEASUREMENT_WINDOW: ("#dbeafe", "#1e40af"),
        DiscrepancyCategory.INCORRECT_SAMPLE_SELECTION: ("#cffafe", "#0e7490"),
        DiscrepancyCategory.MISSING_SENSOR_PACKETS: ("#fee2e2", "#991b1b"),
        DiscrepancyCategory.INCOMPLETE_HISTORICAL_SYNC: ("#ffedd5", "#9a3412"),
        DiscrepancyCategory.SENSOR_ARTIFACT: ("#fef3c7", "#92400e"),
        DiscrepancyCategory.RR_FILTERING_DIFFERENCE: ("#fef9c3", "#854d0e"),
        DiscrepancyCategory.SLEEP_STAGE_DIFFERENCE: ("#e0e7ff", "#3730a3"),
        DiscrepancyCategory.CLOCK_DRIFT: ("#f1f5f9", "#334155"),
        DiscrepancyCategory.WRONG_TIMESTAMP: ("#f1f5f9", "#334155"),
        DiscrepancyCategory.UNSUPPORTED_WHOOP_PROPRIETARY_BEHAVIOR: ("#f3f4f6", "#4b5563"),
        DiscrepancyCategory.INSUFFICIENT_EVIDENCE: ("#f3f4f6", "#6b7280"),
    }
    return mapping.get(category, ("#f3f4f6", "#374151"))


def _badge_color_for_confidence(conf: str) -> tuple[str, str]:
    if conf == "HIGH":
        return ("#dcfce7", "#166534")
    elif conf == "MEDIUM":
        return ("#fef3c7", "#854d0e")
    return ("#f1f5f9", "#475569")


def generate_svg_metric_bars(comparisons: list[MetricComparison], width: int = 760) -> str:
    """Generate an inline SVG horizontal bar chart comparing STRAP vs WHOOP metrics."""
    # Filter numeric metrics that have both values
    plottable = [
        c
        for c in comparisons
        if c.whoop_value is not None and c.strap_value is not None and c.whoop_value > 0
    ][:8]

    if not plottable:
        return "<svg width='100%' height='60'><text x='20' y='35' fill='#888'>No paired numeric metrics to plot</text></svg>"

    row_height = 56
    svg_height = len(plottable) * row_height + 40
    chart_x = 180
    bar_max_width = width - chart_x - 120

    svg_parts = [
        f'<svg viewBox="0 0 {width} {svg_height}" width="100%" height="{svg_height}" xmlns="http://www.w3.org/2000/svg" style="background:#0d1117;border-radius:8px;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;">',
        '<style>',
        '  .label { font-size: 13px; font-weight: 500; fill: #c9d1d9; }',
        '  .val-strap { font-size: 11px; fill: #58a6ff; font-weight: 600; }',
        '  .val-whoop { font-size: 11px; fill: #7ee787; font-weight: 600; }',
        '  .diff { font-size: 11px; fill: #8b949e; }',
        '</style>',
        f'<text x="20" y="24" fill="#f0f6fc" font-size="14" font-weight="600">STRAP vs WHOOP Normalized Comparison</text>',
        f'<rect x="{width - 220}" y="12" width="12" height="12" rx="2" fill="#58a6ff"/>',
        f'<text x="{width - 202}" y="22" fill="#8b949e" font-size="11">STRAP</text>',
        f'<rect x="{width - 140}" y="12" width="12" height="12" rx="2" fill="#7ee787"/>',
        f'<text x="{width - 122}" y="22" fill="#8b949e" font-size="11">WHOOP</text>',
    ]

    for i, m in enumerate(plottable):
        y = 45 + i * row_height
        label = html.escape(m.display_name or m.name.replace("_", " ").title())
        whoop_v = m.whoop_value or 0.0
        strap_v = m.strap_value or 0.0
        max_v = max(whoop_v, strap_v, 1e-3)

        strap_bar_len = (strap_v / max_v) * bar_max_width
        whoop_bar_len = (whoop_v / max_v) * bar_max_width

        diff_str = f"Δ {m.absolute_difference:.1f} {m.unit}" if m.absolute_difference is not None else ""
        if m.percentage_difference is not None:
            diff_str += f" ({m.percentage_difference:.1f}%)"

        svg_parts.append(
            f'<text x="20" y="{y + 20}" class="label">{label}</text>'
            f'<rect x="{chart_x}" y="{y}" width="{strap_bar_len:.1f}" height="14" rx="3" fill="#58a6ff" opacity="0.9"/>'
            f'<text x="{chart_x + strap_bar_len + 8:.1f}" y="{y + 11}" class="val-strap">{strap_v:.1f}</text>'
            f'<rect x="{chart_x}" y="{y + 18}" width="{whoop_bar_len:.1f}" height="14" rx="3" fill="#7ee787" opacity="0.9"/>'
            f'<text x="{chart_x + whoop_bar_len + 8:.1f}" y="{y + 29}" class="val-whoop">{whoop_v:.1f}</text>'
            f'<text x="{width - 15}" y="{y + 20}" class="diff" text-anchor="end">{diff_str}</text>'
        )

    svg_parts.append("</svg>")
    return "\n".join(svg_parts)


def generate_svg_hypnogram(sleep_stages: list[tuple[int, str]], width: int = 760, height: int = 140) -> str:
    """Generate an inline SVG hypnogram showing Awake, REM, Light, and Deep sleep."""
    if not sleep_stages:
        return "<svg width='100%' height='40'><text x='20' y='25' fill='#888'>No sleep stage sequence available</text></svg>"

    stage_order = {"AWAKE": 0, "REM": 1, "LIGHT": 2, "DEEP": 3}
    colors = {"AWAKE": "#f87171", "REM": "#818cf8", "LIGHT": "#60a5fa", "DEEP": "#34d399"}
    labels = ["Awake", "REM", "Light", "Deep"]

    pad_left = 60
    pad_right = 20
    pad_top = 25
    pad_bottom = 25
    plot_w = width - pad_left - pad_right
    plot_h = height - pad_top - pad_bottom

    n_samples = len(sleep_stages)
    step_x = plot_w / max(1, n_samples)

    points: list[str] = []
    svg_parts = [
        f'<svg viewBox="0 0 {width} {height}" width="100%" height="{height}" xmlns="http://www.w3.org/2000/svg" style="background:#0d1117;border-radius:8px;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;">',
        f'<text x="20" y="18" fill="#f0f6fc" font-size="12" font-weight="600">Sleep Architecture Hypnogram</text>',
    ]

    # Y-axis labels and grid
    for idx, stage_name in enumerate(labels):
        y = pad_top + (idx / 3.0) * plot_h
        svg_parts.append(
            f'<line x1="{pad_left}" y1="{y}" x2="{width - pad_right}" y2="{y}" stroke="#30363d" stroke-dasharray="2,2"/>'
            f'<text x="{pad_left - 8}" y="{y + 4}" fill="#8b949e" font-size="10" text-anchor="end">{stage_name}</text>'
        )

    # Hypnogram step polyline
    path_d = ""
    for idx, (_, stage) in enumerate(sleep_stages):
        stage_idx = stage_order.get(stage.upper(), 2)
        x = pad_left + idx * step_x
        y = pad_top + (stage_idx / 3.0) * plot_h
        if idx == 0:
            path_d += f"M {x:.1f},{y:.1f}"
        else:
            prev_y = pad_top + (stage_order.get(sleep_stages[idx - 1][1].upper(), 2) / 3.0) * plot_h
            path_d += f" H {x:.1f} V {y:.1f}"

    svg_parts.append(f'<path d="{path_d}" fill="none" stroke="#58a6ff" stroke-width="2"/>')
    svg_parts.append("</svg>")
    return "\n".join(svg_parts)


class AccuracyReportGenerator:
    """Renders comprehensive offline HTML and Markdown accuracy validation reports."""

    def __init__(self) -> None:
        pass

    def generate_markdown(
        self,
        report: DayComparisonReport,
        diagnoses: list[Diagnosis],
        quality: QualityReport | None = None,
    ) -> str:
        """Render a clean Markdown summary report."""
        lines = [
            f"# STRAP vs WHOOP Accuracy Validation Report: {report.date_key}",
            "",
            "## Summary Metrics Comparison",
            "",
            "| Metric | WHOOP | STRAP | Difference | Discrepancy Category | Confidence |",
            "|:---|:---:|:---:|:---:|:---:|:---:|",
        ]

        diag_map = {d.metric_name: d for d in diagnoses}

        for name, comp in sorted(report.comparisons.items()):
            whoop_str = f"{comp.whoop_value:.1f} {comp.unit}" if comp.whoop_value is not None else "N/A"
            strap_str = f"{comp.strap_value:.1f} {comp.unit}" if comp.strap_value is not None else "N/A"
            diff_str = (
                f"{comp.absolute_difference:.1f} {comp.unit} ({comp.percentage_difference:.1f}%)"
                if comp.percentage_difference is not None
                else "N/A"
            )
            diag = diag_map.get(name)
            cat_str = diag.category.value if diag else "UNKNOWN"
            conf_str = diag.confidence.value if diag else "LOW"
            clean_name = comp.display_name or name.replace("_", " ").title()
            lines.append(f"| **{clean_name}** | {whoop_str} | {strap_str} | {diff_str} | `{cat_str}` | {conf_str} |")

        lines.extend([
            "",
            "## Root-Cause Diagnoses & Ghidra Evidence",
            "",
        ])

        for diag in diagnoses:
            if diag.category == DiscrepancyCategory.INSUFFICIENT_EVIDENCE and (
                "close agreement" in diag.reason.lower()
            ):
                continue
            lines.append(f"### {diag.metric_name.replace('_', ' ').title()}")
            lines.append(f"- **Category:** `{diag.category.value}` ({diag.confidence.value} Confidence)")
            lines.append(f"- **Reason:** {diag.reason}")
            if diag.ghidra_reference:
                ref = diag.ghidra_reference
                lines.append(f"- **Ghidra Finding ({ref.binary}):** `{ref.symbol}` at `{ref.address}`")
                lines.append(f"  > {ref.finding_summary}")
            if diag.remediation_hint:
                lines.append(f"- **Remediation:** {diag.remediation_hint}")
            lines.append("")

        if quality:
            lines.extend([
                "## Sensor Data Quality Telemetry",
                "",
                f"- **Diagnostic Status:** `{quality.status.value}`",
                f"- **Data Coverage:** {quality.coverage_pct:.1f}% ({quality.total_samples}/{quality.expected_samples} samples)",
                f"- **Packet Loss Rate:** {quality.packet_loss_rate_pct:.1f}%",
                f"- **RR Validity Rate:** {quality.rr_validity_rate_pct:.1f}% ({quality.rr_valid_count}/{quality.rr_total_count} valid intervals)",
                f"- **Max Data Gap:** {quality.max_gap_seconds:.1f}s (gaps >5s: {quality.gaps_greater_than_5s})",
                f"- **Stillness Ratio:** {quality.stillness_ratio_pct:.1f}%",
            ])
            if quality.issues:
                lines.append("- **Detected Quality Issues:**")
                for issue in quality.issues:
                    lines.append(f"  - {issue}")
            lines.append("")

        return "\n".join(lines)

    def generate_html(
        self,
        report: DayComparisonReport,
        diagnoses: list[Diagnosis],
        quality: QualityReport | None = None,
        hypnogram_data: list[tuple[int, str]] | None = None,
    ) -> str:
        """Render a fully self-contained offline HTML report."""
        svg_bars = generate_svg_metric_bars(list(report.comparisons.values()))
        svg_hypno = generate_svg_hypnogram(hypnogram_data or [])

        diag_map = {d.metric_name: d for d in diagnoses}

        rows_html: list[str] = []
        for name, comp in sorted(report.comparisons.items()):
            clean_name = html.escape(comp.display_name or name.replace("_", " ").title())
            whoop_val = f"{comp.whoop_value:.1f} <span class='unit'>{comp.unit}</span>" if comp.whoop_value is not None else "&mdash;"
            strap_val = f"{comp.strap_value:.1f} <span class='unit'>{comp.unit}</span>" if comp.strap_value is not None else "&mdash;"

            if comp.percentage_difference is not None:
                color_class = "diff-good" if comp.percentage_difference <= 5.0 else ("diff-mid" if comp.percentage_difference <= 15.0 else "diff-bad")
                diff_html = f"<span class='{color_class}'>{comp.absolute_difference:.1f} {comp.unit} ({comp.percentage_difference:.1f}%)</span>"
            else:
                diff_html = "&mdash;"

            diag = diag_map.get(name)
            if diag:
                bg_cat, text_cat = _badge_color_for_category(diag.category)
                bg_conf, text_conf = _badge_color_for_confidence(diag.confidence.value)
                cat_badge = f"<span class='badge' style='background:{bg_cat};color:{text_cat};'>{diag.category.value}</span>"
                conf_badge = f"<span class='badge' style='background:{bg_conf};color:{text_conf};'>{diag.confidence.value}</span>"
            else:
                cat_badge = "&mdash;"
                conf_badge = "&mdash;"

            rows_html.append(
                f"<tr>"
                f"<td class='metric-name'>{clean_name}</td>"
                f"<td class='num-val'>{whoop_val}</td>"
                f"<td class='num-val'>{strap_val}</td>"
                f"<td class='num-val'>{diff_html}</td>"
                f"<td>{cat_badge}</td>"
                f"<td>{conf_badge}</td>"
                f"</tr>"
            )

        diagnosis_cards_html: list[str] = []
        for diag in diagnoses:
            if diag.category == DiscrepancyCategory.INSUFFICIENT_EVIDENCE and "close agreement" in diag.reason.lower():
                continue
            bg_cat, text_cat = _badge_color_for_category(diag.category)
            bg_conf, text_conf = _badge_color_for_confidence(diag.confidence.value)

            ghidra_box = ""
            if diag.ghidra_reference:
                ref = diag.ghidra_reference
                ghidra_box = f"""
                <div class="ghidra-box">
                    <div class="ghidra-title">WHOOP 5.80.2 Decompiled Ground Truth &bull; <code>{html.escape(ref.symbol)}</code> ({ref.address})</div>
                    <div class="ghidra-body">{html.escape(ref.finding_summary)}</div>
                    <div class="ghidra-sub">{html.escape(ref.relevance)}</div>
                </div>
                """

            remediation_box = ""
            if diag.remediation_hint:
                remediation_box = f"<div class='remediation'><strong>Remediation:</strong> {html.escape(diag.remediation_hint)}</div>"

            card = f"""
            <div class="card">
                <div class="card-header">
                    <span class="card-title">{html.escape(diag.metric_name.replace('_', ' ').title())}</span>
                    <div>
                        <span class="badge" style="background:{bg_cat};color:{text_cat};">{diag.category.value}</span>
                        <span class="badge" style="background:{bg_conf};color:{text_conf};">{diag.confidence.value}</span>
                    </div>
                </div>
                <div class="card-body">
                    <p>{html.escape(diag.reason)}</p>
                    {ghidra_box}
                    {remediation_box}
                </div>
            </div>
            """
            diagnosis_cards_html.append(card)

        quality_box_html = ""
        if quality:
            q_status_bg = "#dcfce7" if quality.status.value == "VALID" else "#fee2e2"
            q_status_text = "#166534" if quality.status.value == "VALID" else "#991b1b"
            issues_list = "".join(f"<li>{html.escape(i)}</li>" for i in quality.issues) if quality.issues else "<li>None (nominal telemetry)</li>"

            quality_box_html = f"""
            <div class="quality-grid">
                <div class="q-metric"><div class="q-val"><span class="badge" style="background:{q_status_bg};color:{q_status_text};font-size:14px;">{quality.status.value}</span></div><div class="q-label">Diagnostic Status</div></div>
                <div class="q-metric"><div class="q-val">{quality.coverage_pct:.1f}%</div><div class="q-label">Data Coverage</div></div>
                <div class="q-metric"><div class="q-val">{quality.packet_loss_rate_pct:.1f}%</div><div class="q-label">Packet Loss Rate</div></div>
                <div class="q-metric"><div class="q-val">{quality.rr_validity_rate_pct:.1f}%</div><div class="q-label">RR Validity</div></div>
                <div class="q-metric"><div class="q-val">{quality.max_gap_seconds:.1f}s</div><div class="q-label">Max Gap</div></div>
                <div class="q-metric"><div class="q-val">{quality.stillness_ratio_pct:.1f}%</div><div class="q-label">Stillness Ratio</div></div>
            </div>
            <div class="quality-issues">
                <strong>Telemetry Observations:</strong>
                <ul>{issues_list}</ul>
            </div>
            """

        html_template = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>STRAP vs WHOOP Accuracy Validation &bull; {html.escape(report.date_key)}</title>
<style>
  :root {{
    --bg: #0f172a;
    --card-bg: #1e293b;
    --border: #334155;
    --text-primary: #f8fafc;
    --text-secondary: #94a3b8;
    --accent: #38bdf8;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    background: var(--bg);
    color: var(--text-primary);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.5;
    padding: 24px;
    max-width: 1080px;
    margin: 0 auto;
  }}
  header {{ margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px solid var(--border); }}
  h1 {{ font-size: 24px; font-weight: 700; color: #fff; }}
  .subtitle {{ color: var(--text-secondary); font-size: 14px; margin-top: 4px; }}
  .section {{ margin-bottom: 32px; }}
  h2 {{ font-size: 18px; font-weight: 600; margin-bottom: 16px; color: var(--accent); }}
  table {{ width: 100%; border-collapse: collapse; margin-bottom: 16px; background: var(--card-bg); border-radius: 8px; overflow: hidden; }}
  th, td {{ padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--border); font-size: 13px; }}
  th {{ background: #162032; color: var(--text-secondary); font-weight: 600; text-transform: uppercase; font-size: 11px; letter-spacing: 0.05em; }}
  tr:last-child td {{ border-bottom: none; }}
  .metric-name {{ font-weight: 600; color: #e2e8f0; }}
  .num-val {{ font-variant-numeric: tabular-nums; }}
  .unit {{ font-size: 11px; color: var(--text-secondary); }}
  .diff-good {{ color: #4ade80; font-weight: 600; }}
  .diff-mid {{ color: #fbbf24; font-weight: 600; }}
  .diff-bad {{ color: #f87171; font-weight: 600; }}
  .badge {{ display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; margin-right: 4px; font-family: monospace; }}
  .card {{ background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; margin-bottom: 16px; overflow: hidden; }}
  .card-header {{ padding: 12px 16px; background: #162032; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--border); }}
  .card-title {{ font-weight: 600; font-size: 15px; color: #f1f5f9; }}
  .card-body {{ padding: 16px; }}
  .ghidra-box {{ margin-top: 12px; background: #0b1329; border-left: 3px solid #6366f1; padding: 10px 14px; border-radius: 0 4px 4px 0; }}
  .ghidra-title {{ font-size: 12px; font-weight: 600; color: #a5b4fc; margin-bottom: 4px; }}
  .ghidra-body {{ font-size: 13px; color: #cbd5e1; }}
  .ghidra-sub {{ font-size: 11px; color: #94a3b8; margin-top: 4px; }}
  .remediation {{ margin-top: 12px; font-size: 13px; color: #38bdf8; background: #0c4a6e22; padding: 8px 12px; border-radius: 4px; border: 1px solid #0284c744; }}
  .quality-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; margin-bottom: 12px; }}
  .q-metric {{ background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 12px; text-align: center; }}
  .q-val {{ font-size: 18px; font-weight: 700; color: #fff; margin-bottom: 2px; }}
  .q-label {{ font-size: 11px; color: var(--text-secondary); text-transform: uppercase; }}
  .quality-issues {{ background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 12px 16px; font-size: 13px; }}
  .quality-issues ul {{ margin-left: 20px; margin-top: 6px; color: var(--text-secondary); }}
  .chart-box {{ margin-bottom: 20px; }}
</style>
</head>
<body>
  <header>
    <h1>STRAP WHOOP Accuracy &amp; Sensor Validation Lab</h1>
    <div class="subtitle">Cycle Analysis &bull; Date: {html.escape(report.date_key)} &bull; Window: {report.cycle_start_unix} &rarr; {report.cycle_end_unix}</div>
  </header>

  <div class="section">
    <h2>Multi-Metric Validation Parity</h2>
    <table>
      <thead>
        <tr>
          <th>Target Metric</th>
          <th>WHOOP Value</th>
          <th>STRAP Value</th>
          <th>Discrepancy</th>
          <th>Root-Cause Category</th>
          <th>Confidence</th>
        </tr>
      </thead>
      <tbody>
        {"".join(rows_html)}
      </tbody>
    </table>
  </div>

  <div class="section chart-box">
    <h2>Sensor &amp; Metric Visualizations</h2>
    {svg_bars}
    <div style="height: 16px;"></div>
    {svg_hypno}
  </div>

  <div class="section">
    <h2>Sensor Data Quality &amp; Telemetry Continuity</h2>
    {quality_box_html}
  </div>

  <div class="section">
    <h2>Root-Cause Diagnoses &amp; Ghidra Byte-Verified References</h2>
    {"".join(diagnosis_cards_html)}
  </div>
</body>
</html>"""
        return html_template

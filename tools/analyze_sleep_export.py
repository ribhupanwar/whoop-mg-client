#!/usr/bin/env python3
"""Read-only audit of STRAP sleep CSVs; no WHOOP scoring or stage re-estimation.

Windows are half-open Unix intervals. ISO arguments must include a UTC offset.
Raw CSVs and generated personal reports should remain outside source control.
"""
import argparse
import collections
import csv
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import statistics
from zoneinfo import ZoneInfo


def instant(value):
    parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.utcoffset() is None:
        raise ValueError('ISO timestamps must include an explicit timezone offset')
    return int(parsed.timestamp())


def contiguous(rows):
    result = []
    for row in rows:
        if not result or row['unix'] != result[-1][-1]['unix'] + 1:
            result.append([])
        result[-1].append(row)
    return result


def rmssd(rows):
    """Mirror Hrv.evaluateRuns: missing RR/seconds and rejected beats break pairs."""
    clean = raw = pairs = 0
    squares = 0.0
    for run in contiguous(rows):
        previous = seed = None
        recent = []
        for row in run:
            values = row['rr']
            raw += len(values)
            if not values:
                previous = seed = None
                recent = []
                continue
            for value in values:
                if not 200 <= value <= 3000:
                    previous = seed = None
                    recent = []
                    continue
                if not recent:
                    if seed is None:
                        seed = value
                        continue
                    if abs(value - seed) > 0.2 * statistics.median([seed, value]):
                        seed = value
                        continue
                    clean += 1
                    recent.append(seed)
                    previous = seed
                    seed = None
                elif abs(value - statistics.median(recent)) > 0.2 * statistics.median(recent):
                    previous = seed = None
                    recent = []
                    continue
                if previous is not None:
                    squares += (value - previous) ** 2
                    pairs += 1
                clean += 1
                recent.append(value)
                recent = recent[-5:]
                previous = value
    return {'raw_beats': raw, 'clean_beats': clean, 'successive_pairs': pairs,
            'rmssd_ms': math.sqrt(squares / pairs) if clean >= 20 and pairs else None}


def load(path):
    data = Path(path).read_bytes()
    rows = []
    bounds = set()
    versions = set()
    for record in csv.DictReader(data.decode('utf-8-sig').splitlines()):
        bounds.add((int(record['window_start_unix']), int(record['window_end_unix'])))
        versions.add(int(record['algorithm_version']))
        rows.append({'unix': int(record['unix']), 'hr': int(record['heart_rate_bpm']),
                     'rr': [int(value) for value in record['rr_ms'].split('|') if value],
                     'motion': float(record['dynamic_accel_g']) if record['dynamic_accel_g'] else None,
                     'stage': record['estimated_stage'], 'band_state': record['band_state'],
                     'hr_quality_flags': record['hr_quality_flags']})
    if len(bounds) != 1 or len(versions) != 1 or not rows:
        raise ValueError('Require one non-empty exported window and algorithm version')
    start, end = next(iter(bounds))
    rows.sort(key=lambda row: row['unix'])
    if len({row['unix'] for row in rows}) != len(rows):
        raise ValueError('Duplicate seconds: packet selection must be resolved before auditing')
    if start >= end or rows[0]['unix'] < start or rows[-1]['unix'] >= end:
        raise ValueError('CSV rows fall outside the declared half-open window')
    return rows, start, end, next(iter(versions)), hashlib.sha256(data).hexdigest()


def audit(rows, start, end, timezone='Asia/Kolkata'):
    if end <= start:
        raise ValueError('Window end must be after its start')
    zone = ZoneInfo(timezone)
    def local(second):
        return dt.datetime.fromtimestamp(second, zone).isoformat()
    selected = [row for row in rows if start <= row['unix'] < end]
    valid = [row for row in selected if 35 <= row['hr'] <= 220]
    quiet = [row for row in valid if row['motion'] is not None
             and math.isfinite(row['motion']) and row['motion'] <= 0.10]
    runs = [run for run in contiguous(quiet) if len(run) >= 300]
    lowest = None
    for run in runs:
        total = sum(row['hr'] for row in run[:300])
        for index in range(len(run) - 299):
            if index:
                total += run[index + 299]['hr'] - run[index - 1]['hr']
            if lowest is None or total / 300 < lowest['bpm']:
                lowest = {'bpm': total / 300, 'start': local(run[index]['unix']),
                          'end_exclusive': local(run[index + 299]['unix'] + 1)}
    hrv = None
    for run in sorted(runs, key=len, reverse=True):
        candidate = rmssd(run)
        if candidate['rmssd_ms'] is not None:
            hrv = {**candidate, 'window_seconds': len(run), 'start': local(run[0]['unix']),
                   'end_exclusive': local(run[-1]['unix'] + 1)}
            break
    missing = []
    cursor = start
    for row in selected:
        if row['unix'] > cursor:
            missing.append({'start': local(cursor), 'end_exclusive': local(row['unix']),
                            'seconds': row['unix'] - cursor})
        cursor = row['unix'] + 1
    if cursor < end:
        missing.append({'start': local(cursor), 'end_exclusive': local(end), 'seconds': end - cursor})
    rr_gaps = sorted(contiguous([row for row in selected if not row['rr']]), key=len, reverse=True)
    return {'start': local(start), 'end_exclusive': local(end), 'expected_seconds': end - start,
            'observed_seconds': len(selected), 'valid_hr_seconds': len(valid),
            'missing_seconds': end - start - len(selected), 'missing_intervals': missing,
            'hr_mean_bpm': statistics.mean(row['hr'] for row in valid) if valid else None,
            'hr_median_bpm': statistics.median(row['hr'] for row in valid) if valid else None,
            'minimum_quiet_300_second_hr': lowest, 'longest_usable_quiet_hrv': hrv,
            'stored_stage_observed_seconds': dict(collections.Counter(row['stage'] or 'unclassified' for row in selected)),
            'stages_reestimated': False,
            'missing_rr_seconds': sum(not row['rr'] for row in selected),
            'longest_missing_rr_run_seconds': len(rr_gaps[0]) if rr_gaps else 0,
            'band_states_opaque': dict(collections.Counter(row['band_state'] for row in selected)),
            'hr_quality_flags_opaque': dict(collections.Counter(row['hr_quality_flags'] for row in selected))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv')
    parser.add_argument('--timezone', default='Asia/Kolkata')
    parser.add_argument('--reference-start', type=instant)
    parser.add_argument('--reference-end', type=instant)
    args = parser.parse_args()
    if (args.reference_start is None) != (args.reference_end is None):
        parser.error('Supply both reference bounds with explicit timezone offsets')
    rows, start, end, version, digest = load(args.csv)
    report = {'source_sha256': digest, 'algorithm_version': version,
              'exported_window': audit(rows, start, end, args.timezone)}
    if args.reference_start is not None:
        report['reference_window_available_data_only'] = audit(rows, args.reference_start, args.reference_end, args.timezone)
        lo, hi = max(start, args.reference_start), min(end, args.reference_end)
        report['intersection'] = audit(rows, lo, hi, args.timezone) if lo < hi else None
    print(json.dumps(report, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()

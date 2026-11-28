"""Offline sleep evidence comparison; never writes or changes production scoring.
Uses a 1 Hz wrist-gravity approximation and 30 s cardiac epochs, not PSG or
an implementation of OpenStrap's complete stager. Input: STRAP history.sqlite.
"""
import argparse
import json
import math
import sqlite3
from pathlib import Path
from statistics import median


def evidence(rows, start, end):
    if not 0 < end - start <= 86400:
        raise ValueError('window must be 1..86400 seconds (exclusive end)')
    n = end - start
    unique, conflicts = {}, set()
    for t, row in rows:
        if start <= t < end:
            if t in unique and unique[t] != row:
                conflicts.add(t)
            unique[t] = row
    hr, angle, motion, rr = ([None] * n for _ in range(4))
    for t, row in unique.items():
        i = t - start
        if t in conflicts:
            continue
        h, m, temp = (row.get(k) for k in ('heartRate', 'dynamicAccelG', 'skinTempC'))
        if not isinstance(h, (float, int)) or not 35 <= h <= 220:
            continue
        if isinstance(temp, (float, int)) and -20 <= temp < 25 and temp != 0 and isinstance(m, (float, int)) and 0 <= m < .005:
            continue
        hr[i] = h
        if isinstance(m, (float, int)) and math.isfinite(m) and m >= 0:
            motion[i] = m
        xyz = [row.get(k) for k in ('gravityXG', 'gravityYG', 'gravityZG')]
        if all(isinstance(x, (float, int)) and math.isfinite(x) for x in xyz):
            x, y, z = xyz
            if .7 <= math.sqrt(x*x + y*y + z*z) <= 1.3:
                angle[i] = math.degrees(math.atan2(z, math.hypot(x, y)))
        beats = row.get('rrIntervalsMS') or []
        rr[i] = sum(isinstance(b, (float, int)) and 300 <= b <= 2000 for b in beats)
    smooth = [None] * n
    for i in range(n):
        v = angle[max(0, i-2):min(n, i+3)]
        if len(v) == 5 and all(x is not None for x in v):
            smooth[i] = median(v)
    # Five-second change, requiring complete underlying centered windows.
    delta = [None] * n
    for i in range(5, n):
        if all(x is not None for x in smooth[i-5:i+1]):
            delta[i] = abs(smooth[i] - smooth[i-5])
    movement, missing = [0], [0]
    for d in delta:
        movement.append(movement[-1] + int(d is not None and d >= 5))
        missing.append(missing[-1] + int(d is None))
    rest = [None] * n
    for i in range(n):
        hi = min(n, i+300)
        if movement[hi] > movement[i]:
            rest[i] = False
        elif hi-i == 300 and missing[hi] == missing[i]:
            rest[i] = True
    epochs = []
    for i in range(0, n, 30):
        hi = min(n, i+30)
        hs = [x for x in hr[i:hi] if x is not None]
        ms = [x for x in motion[i:hi] if x is not None]
        epochs.append(dict(startUnix=start+i, seconds=hi-i,
            hrSeconds=len(hs), medianHR=median(hs) if len(hs)*2 >= hi-i else None,
            motionSeconds=len(ms), medianMotionG=median(ms) if len(ms)*2 >= hi-i else None,
            rrSeconds=sum(x is not None and x > 0 for x in rr[i:hi]),
            wristRestSeconds=rest[i:hi].count(True), wristRestRuleFailedSeconds=rest[i:hi].count(False),
            wristUnknownSeconds=rest[i:hi].count(None)))
    h = [x['medianHR'] for x in epochs if x['medianHR'] is not None]
    whole = median(h) if len(h)*2 >= len(epochs) else None
    for i, e in enumerate(epochs):
        neighborhood = epochs[max(0,i-90):min(len(epochs), i+90)]
        local = [x['medianHR'] for x in neighborhood if x['medianHR'] is not None]
        baseline = median(local) if len(local) >= 60 and len(local)*2 >= len(neighborhood) else None
        e['wholeNightHRBaseline'] = whole
        e['local90mHRBaseline'] = baseline
        e['wholeNightHRDelta'] = e['medianHR']-whole if e['medianHR'] is not None and whole is not None else None
        e['localHRDelta'] = e['medianHR']-baseline if e['medianHR'] is not None and baseline is not None else None
    comparable = [e for e in epochs if e['wholeNightHRDelta'] is not None and e['localHRDelta'] is not None]
    return dict(startUnix=start, endUnixExclusive=end, source='offline shadow evidence only; no stage assignments',
        seconds=n, validHRSeconds=sum(x is not None for x in hr), validGravitySeconds=sum(x is not None for x in angle),
        wristRestSeconds=rest.count(True), wristRestRuleFailedSeconds=rest.count(False), wristUnknownSeconds=rest.count(None),
        wholeNightHRBaseline=whole, comparableEpochs=len(comparable),
        wholeOnlyElevatedEpochs=sum(e['wholeNightHRDelta'] >= 10 > e['localHRDelta'] for e in comparable),
        localOnlyElevatedEpochs=sum(e['localHRDelta'] >= 10 > e['wholeNightHRDelta'] for e in comparable), epochs=epochs)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('database', type=Path)
    p.add_argument('--start', type=int, required=True)
    p.add_argument('--end', type=int, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    if not 0 < a.end - a.start <= 86400:
        p.error('window must be 1..86400 seconds')
    with sqlite3.connect(a.database.resolve().as_uri()+'?mode=ro', uri=True) as db:
        rows = ((t,json.loads(raw)) for t,raw in db.execute('SELECT unix,payload FROM history_sample WHERE unix >= ? AND unix < ? ORDER BY unix',(a.start,a.end)))
        report = evidence(rows,a.start,a.end)
    # Output is private and explicit. Never overwrite an existing report.
    with a.output.open('x', encoding='utf-8') as f:
        json.dump(report,f,indent=2,allow_nan=False)
    print(json.dumps({k:v for k,v in report.items() if k!='epochs'},indent=2))


if __name__ == '__main__':
    main()

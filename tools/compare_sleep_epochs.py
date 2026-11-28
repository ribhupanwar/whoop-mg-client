"""Compare two independently staged nights on the same UTC 30-second grid.

Input CSV columns: startUnix,stage; stage = wake/light/deep/rem/unknown.
No offset fitting, imputation, label generation, or production writes.
A vendor reference is not PSG ground truth.
"""
import argparse
import csv
import json
from pathlib import Path

STAGES = ("wake", "light", "deep", "rem")
VALID = set(STAGES) | {"unknown"}


def load_epochs(path):
    with path.open(newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise ValueError("empty epoch file")
    result = {}
    for row in rows:
        t = int(row["startUnix"])
        label = row["stage"].strip().lower()
        if t < 0 or label not in VALID:
            raise ValueError("invalid timestamp or stage")
        if t in result:
            raise ValueError("duplicate epoch timestamp")
        result[t] = label
    return result


def compare(candidate, reference):
    if not candidate or not reference:
        raise ValueError("both nights require epochs")
    origin = min(min(candidate), min(reference))
    end = max(max(candidate), max(reference)) + 30
    if end - origin > 86400 or any((t-origin) % 30 for t in list(candidate)+list(reference)):
        raise ValueError("need a common UTC 30-second grid within 24 hours")
    if any(s not in VALID for s in list(candidate.values())+list(reference.values())):
        raise ValueError("invalid stage")
    matrix = {a: {b: 0 for b in STAGES} for a in STAGES}
    counts = {"both": 0, "candidate_only": 0, "reference_only": 0, "neither": 0}
    for t in range(origin, end, 30):
        a, b = candidate.get(t, "unknown"), reference.get(t, "unknown")
        if a in STAGES and b in STAGES:
            counts["both"] += 1
            matrix[b][a] += 1
        elif a in STAGES:
            counts["candidate_only"] += 1
        elif b in STAGES:
            counts["reference_only"] += 1
        else:
            counts["neither"] += 1
    paired = counts["both"]
    match = sum(matrix[s][s] for s in STAGES)

    def metrics(rows):
        # Boundary and duration metrics require complete observations
        # over that method's declared window. Never equate unknown with wake.
        lo, hi = min(rows), max(rows)
        expected = list(range(lo, hi+30, 30))
        if any(rows.get(t, "unknown") == "unknown" for t in expected):
            return None
        asleep = [t for t in expected if rows[t] != "wake"]
        if not asleep:
            return None
        onset, wake = asleep[0], asleep[-1]+30
        return dict(onsetUnix=onset, finalWakeUnix=wake,
                    totalSleepSeconds=len(asleep)*30,
                    wasoSeconds=sum(rows[t]=="wake" for t in range(onset,wake,30))*30,
                    stageSeconds={s:sum(rows[t]==s for t in expected)*30 for s in STAGES})
    a, b = metrics(candidate), metrics(reference)
    delta = None if a is None or b is None else {
        "onsetSeconds": a["onsetUnix"]-b["onsetUnix"],
        "wakeSeconds": a["finalWakeUnix"]-b["finalWakeUnix"],
        "totalSleepSeconds": a["totalSleepSeconds"]-b["totalSleepSeconds"],
        "wasoSeconds": a["wasoSeconds"]-b["wasoSeconds"],
        "stageSeconds": {s:a["stageSeconds"][s]-b["stageSeconds"][s] for s in STAGES}}
    return dict(note="reference agreement, not PSG accuracy; boundaries inferred from staged epochs",
                coverageEpochs=counts, pairedAgreement=match/paired if paired else None,
                pairedConfusionMatrixReferenceRows=matrix,
                candidate=a, reference=b, signedDifferences=delta)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("candidate", type=Path)
    p.add_argument("reference", type=Path)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    report = compare(load_epochs(a.candidate), load_epochs(a.reference))
    with a.output.open("x", encoding="utf-8") as f:
        json.dump(report, f, indent=2, allow_nan=False)


if __name__ == "__main__":
    main()

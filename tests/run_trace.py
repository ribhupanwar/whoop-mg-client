"""Run Python golden fixtures with trace diagnostics."""

import json
from tests.golden_fixtures import FIXTURES, run_python_fixtures, print_summary
from whoop.health import detect_sleep, merge_nocturnal_periods

def trace_sink(event):
    print(f"  TRACE: {json.dumps(event, default=str)}")

def run_with_trace():
    """Run fixtures with trace output for failing cases."""
    failing_names = [
        "awake_in_bed_30min_no_hr_drop",
        "awake_in_bed_60min_no_hr_drop", 
        "awake_with_hr_drop_false_positive_risk",
        "delayed_sleep_onset_90min",
        "bathroom_break_31min_split",
        "missing_ble_packets_gap",
        "morning_lying_awake_no_extend"
    ]
    
    for fixture in FIXTURES:
        if fixture.name not in failing_names:
            continue
            
        print(f"\n{'='*60}")
        print(f"TRACE: {fixture.name}")
        print(f"Description: {fixture.description}")
        
        periods = detect_sleep(fixture.samples, trace_sink=trace_sink)
        merged = merge_nocturnal_periods(periods, fixture.samples)
        
        print(f"  Result: {len(merged)} periods")
        for i, p in enumerate(merged):
            print(f"    Period {i+1}: onset={p.start_unix}, wake={p.end_unix}, dur={p.duration_s}s, meanHR={p.mean_hr:.1f}")

if __name__ == "__main__":
    run_with_trace()
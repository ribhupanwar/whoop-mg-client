#!/usr/bin/env python3
"""
benchmark_ble_pipeline.py - Empirical performance benchmark for STRAP / WHOOP runtime pipeline.

Benchmarks:
1. CRC-16 MODBUS: Bit-by-bit loop vs Precomputed 256-entry table.
2. Gen5 Frame Reassembly: O(N^2) Array slice reallocation vs O(1) Sliding Cursor.
3. V18 Record Numeric Scaling: Dynamic pow(10, n) vs Precomputed Fixed Constants.
4. History DB Insertion: SELECT-before-write vs INSERT ON CONFLICT DO NOTHING fast-path.
5. Daily Analysis Date Partitioning: Per-sample calendar query vs Day-range caching.
"""

import time
import random
import sqlite3
import datetime

def benchmark_crc16():
    # Generate 1 MB of synthetic BLE payload bytes
    random.seed(42)
    data = bytes([random.randint(0, 255) for _ in range(1_000_000)])
    
    # 1. Bitwise loop
    def crc16_bitwise(data_bytes):
        crc = 0xFFFF
        for byte in data_bytes:
            crc ^= byte
            for _ in range(8):
                if crc & 1:
                    crc = (crc >> 1) ^ 0xA001
                else:
                    crc = crc >> 1
        return crc

    # 2. Precomputed 256-entry table
    table = []
    for i in range(256):
        val = i
        for _ in range(8):
            if val & 1:
                val = (val >> 1) ^ 0xA001
            else:
                val = val >> 1
        table.append(val)

    def crc16_table(data_bytes):
        crc = 0xFFFF
        for byte in data_bytes:
            idx = (crc ^ byte) & 0xFF
            crc = (crc >> 8) ^ table[idx]
        return crc

    # Measure bitwise
    t0 = time.perf_counter()
    res1 = crc16_bitwise(data)
    t_bitwise = time.perf_counter() - t0

    # Measure table
    t0 = time.perf_counter()
    res2 = crc16_table(data)
    t_table = time.perf_counter() - t0

    assert res1 == res2, f"CRC mismatch: {hex(res1)} vs {hex(res2)}"
    return {
        "bytes": len(data),
        "t_bitwise_sec": t_bitwise,
        "t_table_sec": t_table,
        "speedup": t_bitwise / t_table
    }

def benchmark_reassembler():
    # Simulate 50,000 fragments being appended to a buffer and frames extracted
    # Frame format: 0xAA 0x55 [len_lo] [len_hi] [cmd] [seq] [crc_lo] [crc_hi] [payload 32 bytes]
    frame_payload_len = 32
    frame_total_len = 8 + frame_payload_len
    num_frames = 10_000
    stream = bytearray()
    for seq in range(num_frames):
        stream.extend([0xAA, 0x55, frame_payload_len & 0xFF, (frame_payload_len >> 8) & 0xFF, 0x18, seq & 0xFF, 0x00, 0x00])
        stream.extend(b"\x00" * frame_payload_len)

    # 1. Naive reallocation buffer (removeFirst/slicing)
    t0 = time.perf_counter()
    buf = bytearray(stream)
    frames_naive = 0
    while len(buf) >= frame_total_len:
        if buf[0] == 0xAA and buf[1] == 0x55:
            frames_naive += 1
            buf = buf[frame_total_len:]
        else:
            buf = buf[1:]
    t_naive = time.perf_counter() - t0

    # 2. Sliding cursor buffer
    t0 = time.perf_counter()
    buf = bytearray(stream)
    cursor = 0
    frames_cursor = 0
    while len(buf) - cursor >= frame_total_len:
        if buf[cursor] == 0xAA and buf[cursor + 1] == 0x55:
            frames_cursor += 1
            cursor += frame_total_len
        else:
            cursor += 1
        if cursor >= 4096 and cursor > len(buf) // 2:
            del buf[:cursor]
            cursor = 0
    t_cursor = time.perf_counter() - t0

    assert frames_naive == frames_cursor == num_frames
    return {
        "frames": num_frames,
        "t_naive_sec": t_naive,
        "t_cursor_sec": t_cursor,
        "speedup": t_naive / t_cursor
    }

def benchmark_scaling():
    iterations = 200_000
    values = [random.uniform(-16.0, 16.0) for _ in range(iterations)]

    # Dynamic pow
    t0 = time.perf_counter()
    res1 = []
    for v in values:
        scale = 10.0 ** 4
        res1.append(round(v * scale) / scale)
    t_dynamic = time.perf_counter() - t0

    # Fixed scale constant
    t0 = time.perf_counter()
    res2 = []
    scale_const = 10_000.0
    for v in values:
        res2.append(round(v * scale_const) / scale_const)
    t_fixed = time.perf_counter() - t0

    return {
        "iterations": iterations,
        "t_dynamic_sec": t_dynamic,
        "t_fixed_sec": t_fixed,
        "speedup": t_dynamic / t_fixed
    }

def benchmark_db_insertion():
    # In-memory SQLite with 10,000 rows
    num_rows = 10_000
    rows = [(1700000000 + i, b"test_payload_data_v18") for i in range(num_rows)]

    # 1. SELECT before INSERT
    db1 = sqlite3.connect(":memory:")
    db1.execute("CREATE TABLE history_sample (unix INTEGER PRIMARY KEY, payload BLOB)")
    t0 = time.perf_counter()
    cur1 = db1.cursor()
    for unix, payload in rows:
        cur1.execute("SELECT payload FROM history_sample WHERE unix = ?", (unix,))
        row = cur1.fetchone()
        if row is None:
            cur1.execute("INSERT INTO history_sample (unix, payload) VALUES (?, ?)", (unix, payload))
    db1.commit()
    t_select_insert = time.perf_counter() - t0

    # 2. INSERT ON CONFLICT DO NOTHING fast-path
    db2 = sqlite3.connect(":memory:")
    db2.execute("CREATE TABLE history_sample (unix INTEGER PRIMARY KEY, payload BLOB)")
    t0 = time.perf_counter()
    cur2 = db2.cursor()
    for unix, payload in rows:
        cur2.execute("INSERT INTO history_sample (unix, payload) VALUES (?, ?) ON CONFLICT(unix) DO NOTHING", (unix, payload))
    db2.commit()
    t_fast_insert = time.perf_counter() - t0

    return {
        "rows": num_rows,
        "t_select_insert_sec": t_select_insert,
        "t_fast_insert_sec": t_fast_insert,
        "speedup": t_select_insert / t_fast_insert
    }

def benchmark_daily_partitioning():
    # 50,000 timestamps across 30 days
    num_samples = 50_000
    start_ts = 1700000000
    timestamps = [start_ts + i * 50 for i in range(num_samples)]

    # 1. Naive: datetime conversion on every single sample
    t0 = time.perf_counter()
    by_day_naive = {}
    for ts in timestamps:
        dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
        key = dt.strftime("%Y-%m-%d")
        if key not in by_day_naive:
            by_day_naive[key] = []
        by_day_naive[key].append(ts)
    t_naive = time.perf_counter() - t0

    # 2. Cached day range: range check for contiguous samples
    t0 = time.perf_counter()
    by_day_cached = {}
    cur_key = ""
    cur_start = 0
    cur_end = 0
    for ts in timestamps:
        if cur_start <= ts < cur_end:
            by_day_cached[cur_key].append(ts)
        else:
            dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
            cur_key = dt.strftime("%Y-%m-%d")
            # compute midnight boundaries for day
            day_start = dt.replace(hour=0, minute=0, second=0, microsecond=0)
            cur_start = int(day_start.timestamp())
            cur_end = cur_start + 86400
            if cur_key not in by_day_cached:
                by_day_cached[cur_key] = []
            by_day_cached[cur_key].append(ts)
    t_cached = time.perf_counter() - t0

    assert len(by_day_naive) == len(by_day_cached)
    return {
        "samples": num_samples,
        "t_naive_sec": t_naive,
        "t_cached_sec": t_cached,
        "speedup": t_naive / t_cached
    }

def main():
    print("=" * 60)
    print("STRAP / WHOOP RUNTIME PERFORMANCE BENCHMARK SUITE")
    print("=" * 60)

    print("\n[1/5] Benchmarking CRC-16 MODBUS (1,000,000 bytes)...")
    res_crc = benchmark_crc16()
    print(f"  Bitwise loop:       {res_crc['t_bitwise_sec']:.4f} s ({res_crc['bytes']/res_crc['t_bitwise_sec']/1e6:.2f} MB/s)")
    print(f"  Table-driven:       {res_crc['t_table_sec']:.4f} s ({res_crc['bytes']/res_crc['t_table_sec']/1e6:.2f} MB/s)")
    print(f"  Speedup factor:     {res_crc['speedup']:.2f}x")

    print("\n[2/5] Benchmarking Gen5 Frame Reassembly (10,000 frames)...")
    res_reassembly = benchmark_reassembler()
    print(f"  Naive slice copy:   {res_reassembly['t_naive_sec']:.4f} s")
    print(f"  Sliding cursor:     {res_reassembly['t_cursor_sec']:.4f} s")
    print(f"  Speedup factor:     {res_reassembly['speedup']:.2f}x")

    print("\n[3/5] Benchmarking V18 Numeric Scaling (200,000 operations)...")
    res_scale = benchmark_scaling()
    print(f"  Dynamic pow(10, n): {res_scale['t_dynamic_sec']:.4f} s")
    print(f"  Fixed constants:    {res_scale['t_fixed_sec']:.4f} s")
    print(f"  Speedup factor:     {res_scale['speedup']:.2f}x")

    print("\n[4/5] Benchmarking SQLite Insertion (10,000 rows)...")
    res_db = benchmark_db_insertion()
    print(f"  SELECT + INSERT:    {res_db['t_select_insert_sec']:.4f} s")
    print(f"  ON CONFLICT DO NOT: {res_db['t_fast_insert_sec']:.4f} s")
    print(f"  Speedup factor:     {res_db['speedup']:.2f}x")

    print("\n[5/5] Benchmarking Daily Partitioning (50,000 samples)...")
    res_part = benchmark_daily_partitioning()
    print(f"  Per-sample parsing: {res_part['t_naive_sec']:.4f} s")
    print(f"  Cached day range:   {res_part['t_cached_sec']:.4f} s")
    print(f"  Speedup factor:     {res_part['speedup']:.2f}x")

    print("\n" + "=" * 60)
    print("BENCHMARK SUMMARY COMPLETE")
    print("=" * 60)

if __name__ == "__main__":
    main()

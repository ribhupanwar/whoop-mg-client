#!/usr/bin/env python3
"""Offline, read-only inventory of an iOS WHOOP container ZIP. No raw records printed."""
import collections, json, os, re, sqlite3, sys, tempfile, zipfile
from pathlib import Path
from pathlib import PurePosixPath
archive=sys.argv[1]
MAX_FILE=150*1024*1024
def safe_name(n):
    p=PurePosixPath(n)
    return not p.is_absolute() and '..' not in p.parts
def is_sqlite(data):
    return data[:16]==b'SQLite format 3\x00'
with zipfile.ZipFile(archive) as z:
    files=[i for i in z.infolist() if not i.is_dir() and safe_name(i.filename)]
    kinds=collections.Counter(PurePosixPath(i.filename).suffix.lower() or '(none)' for i in files)
    print("FILE_COUNT",len(files),"EXTENSIONS",json.dumps(kinds.most_common(20)))
    dbs=[i for i in files if i.file_size<=MAX_FILE and (i.filename.lower().endswith(('.sqlite','.sqlite3','.db','.storedata')) or 'sqlite' in i.filename.lower())]
    print("DATABASE_CANDIDATES",len(dbs))
    by_path={i.filename:i for i in files}
    for i in dbs[:80]:
        try:
            with z.open(i) as source:
                data=source.read(MAX_FILE+1)
            if not is_sqlite(data): continue
            with tempfile.TemporaryDirectory(prefix="whoop-inspect-") as workdir:
                # SQLite needs the matching -wal and -shm beside the main DB.
                # Preserve the original DB basename so SQLite finds its sidecars.
                dbpath=Path(workdir)/PurePosixPath(i.filename).name
                dbpath.write_bytes(data)
                wal_present=False
                for suffix in ("-wal","-shm"):
                    sidecar=by_path.get(i.filename+suffix)
                    if sidecar and sidecar.file_size<=MAX_FILE:
                        (Path(str(dbpath)+suffix)).write_bytes(z.read(sidecar))
                        if suffix=="-wal": wal_present=True
                # The copy is disposable; never modify the backup archive.
                con=sqlite3.connect(dbpath.as_uri()+"?mode=ro",uri=True)
                print("DB_SIDECAR",dbpath.name,"WAL",wal_present)
                rows=con.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
                names=[x[0] for x in rows]
                relevant=[n for n in names if re.search(r'heart|pulse|activity|workout|sleep|sample|sensor|biometric|rr|hrv',n,re.I)]
                nonempty=0
                for table_name in names[:100]:
                    if table_name.startswith("sqlite_"): continue
                    try:
                        safe_table='"'+table_name.replace('"','""')+'"'
                        if con.execute("SELECT 1 FROM "+safe_table+" LIMIT 1").fetchone(): nonempty+=1
                    except sqlite3.DatabaseError: pass
                print("DB_NONEMPTY_TABLE_COUNT",dbpath.name,nonempty)
                # Report counts for health-related tables, including databases
                # other than whoop.sqlite; no rows or health values are emitted.
                health_counts=[]
                for table_name in relevant[:50]:
                    try:
                        safe_table='"'+table_name.replace('"','""')+'"'
                        n=con.execute("SELECT COUNT(*) FROM "+safe_table).fetchone()[0]
                        if n: health_counts.append({"table":table_name,"rows":n})
                    except sqlite3.DatabaseError: pass
                if health_counts:
                    print("NONEMPTY_HEALTH_TABLES",dbpath.name,json.dumps(health_counts[:30]))
                print("DB",PurePosixPath(i.filename).name,"TABLES",len(names),"RELEVANT",json.dumps(relevant[:50]))
                for name in relevant[:20]:
                    cols=con.execute('PRAGMA table_info("'+name.replace('"','""')+'")').fetchall()
                    print("SCHEMA",name,json.dumps([c[1] for c in cols][:35]))
                # Privacy-safe diagnostics: only aggregates, never row values or identifiers.
                for table in ("ZACTIVITYENTITY", "ZCACHEDHEARTDATAENTITY", "ZACTIVITYLOCATIONDATAENTITY"):
                    if table not in names: continue
                    quoted='"'+table.replace('"','""')+'"'
                    count=con.execute("SELECT COUNT(*) FROM "+quoted).fetchone()[0]
                    print("RECORD_COUNT",table,count)
                    columns={c[1] for c in con.execute("PRAGMA table_info("+quoted+")")}
                    for field in (("ZRAWSTRAINSCORE","ZSCALEDSTRAINSCORE") if table=="ZACTIVITYENTITY" else ("ZHEARTRATE","ZTIMESTAMP") if table=="ZCACHEDHEARTDATAENTITY" else ("ZTIMESTAMP",)):
                        if field not in columns: continue
                        qfield='"'+field+'"'
                        nonnull=con.execute("SELECT COUNT("+qfield+") FROM "+quoted).fetchone()[0]
                        print("FIELD_COVERAGE",table,field,nonnull,count)
                    if table=="ZACTIVITYENTITY" and {"ZRAWSTRAINSCORE","ZSCALEDSTRAINSCORE"}.issubset(columns):
                        pair=con.execute("SELECT COUNT(*) FROM "+quoted+" WHERE ZRAWSTRAINSCORE IS NOT NULL AND ZSCALEDSTRAINSCORE IS NOT NULL").fetchone()[0]
                        print("STRAIN_PAIRED_RECORDS",pair)
                    if table=="ZCACHEDHEARTDATAENTITY" and "ZTIMESTAMP" in columns:
                        # Distribution of positive sampling intervals, rounded to whole seconds.
                        # No timestamps or individual HR readings leave the runner.
                        intervals=con.execute("SELECT ZTIMESTAMP FROM "+quoted+" WHERE ZTIMESTAMP IS NOT NULL ORDER BY ZTIMESTAMP LIMIT 20000").fetchall()
                        diffs=[b[0]-a[0] for a,b in zip(intervals,intervals[1:]) if 0 < b[0]-a[0] <= 3600]
                        if diffs:
                            diffs.sort()
                            print("HR_SAMPLE_INTERVAL_SECONDS_P50_P90",round(diffs[len(diffs)//2]),round(diffs[int((len(diffs)-1)*.9)]),"SAMPLES",len(diffs))
                con.close()
        except Exception as exc:
            print("DB_ERROR",PurePosixPath(i.filename).suffix,type(exc).__name__)
    # Identify non-SQLite storage formats without reading or logging sensitive values.
    extensions=collections.Counter()
    signatures=collections.Counter()
    likely_paths=collections.Counter()
    for entry in files:
        if entry.file_size>MAX_FILE: continue
        suffix=PurePosixPath(entry.filename).suffix.lower() or "(none)"
        extensions[suffix]+=1
        if suffix in (".webp",".png",".jpg",".jpeg",".ktx",".sqlite-wal",".sqlite-shm",".db-wal",".db-shm",".sqlite3-wal",".sqlite3-shm"):
            continue
        try:
            with z.open(entry) as fh: header=fh.read(64)
            if header.startswith(b"SQLite format 3"): kind="sqlite"
            elif header.startswith(b"bplist00"): kind="binary-plist"
            elif header.startswith(b"{") or header.startswith(b"["): kind="json-like"
            elif header.startswith(b"<?xml"): kind="xml"
            elif header.startswith(b"PK\\x03\\x04"): kind="zip"
            elif header.startswith(b"\\x1f\\x8b"): kind="gzip"
            elif header.startswith(b"\\x28\\xb5\\x2f\\xfd"): kind="zstd"
            elif header.startswith(b"\\x04\\x22\\x4d\\x18"): kind="lz4"
            elif not header: kind="empty"
            else: kind="other-binary-or-text"
            signatures[(suffix,kind)]+=1
            if re.search(r'cache|database|leveldb|realm|rocksdb|activity|health|workout|heart|sensor|sleep|metrics',entry.filename,re.I):
                likely_paths[(suffix,kind)]+=1
        except Exception:
            signatures[(suffix,"unreadable")]+=1
    # Storage topology only: group candidate files by recognized database
    # families, without printing paths, identifiers, or file contents.
    families=collections.Counter()
    family_bytes=collections.Counter()
    for entry in files:
        lower=entry.filename.lower()
        if lower.endswith(".mdb") or "/data.mdb" in lower or "/lock.mdb" in lower:
            family="lmdb-candidate"
        elif any(token in lower for token in ("/leveldb/","/indexeddb/","/rocksdb/")):
            family="key-value-store"
        elif any(token in lower for token in ("/cache/","/caches/","/cache.db","/cfnetwork/")):
            family="cache"
        elif lower.endswith((".sqlite",".sqlite3",".db")):
            family="sqlite"
        elif lower.endswith((".plist",".json",".state")):
            family="plist-json-state"
        else:
            family="other"
        families[family]+=1
        family_bytes[family]+=entry.file_size
    # Cache-only structural probe: no names, URLs, identifiers or values printed.
    # A small header read keeps memory bounded even for large cached responses.
    cache_signatures=collections.Counter()
    cache_size_buckets=collections.Counter()
    cache_total=0
    for entry in files:
        lower=entry.filename.lower()
        if not any(t in lower for t in ("/cache/","/caches/","/cache.db","/cfnetwork/")):
            continue
        cache_total+=1
        size=entry.file_size
        bucket="empty" if size==0 else "<1KB" if size<1024 else "1-64KB" if size<65536 else "64KB-1MB" if size<1048576 else "1-10MB" if size<10485760 else ">=10MB"
        cache_size_buckets[bucket]+=1
        try:
            with z.open(entry) as source:
                head=source.read(4096)
            if head.startswith(b"SQLite format 3"): fmt="sqlite"
            elif head.startswith(b"bplist00"): fmt="binary-plist"
            elif head.startswith(bytes.fromhex("1f8b")): fmt="gzip"
            elif head.startswith(bytes.fromhex("28b52ffd")): fmt="zstd"
            elif head.startswith(bytes.fromhex("04224d18")): fmt="lz4"
            elif head.startswith(bytes.fromhex("504b0304")): fmt="zip"
            elif head.lstrip().startswith((b"{",b"[")): fmt="json-like"
            elif head.lstrip().startswith(b"<?xml"): fmt="xml"
            elif not head: fmt="empty"
            elif head[:4096].count(b"\\x00") > len(head)//8: fmt="binary"
            elif all((b in (9,10,13) or 32<=b<127) for b in head[:256]): fmt="ascii-text"
            else: fmt="opaque"
            cache_signatures[fmt]+=1
        except Exception:
            cache_signatures["unreadable"]+=1
    # Privacy-preserving schema discovery on cached structured files.
    # Only aggregate field names from JSON objects; never print values, URLs,
    # IDs, raw blobs or paths. Limit parsing to 1 MiB per entry.
    json_key_counts=collections.Counter()
    json_parsed=0
    cache_db_tables=collections.Counter()
    for entry in files:
        lower=entry.filename.lower()
        if not any(t in lower for t in ("/cache/","/caches/","/cache.db","/cfnetwork/")):
            continue
        if entry.file_size==0 or entry.file_size>1024*1024: continue
        try:
            with z.open(entry) as source: data=source.read(1024*1024+1)
            if data.lstrip().startswith((b"{",b"[")):
                obj=json.loads(data)
                json_parsed+=1
                items=[obj] if isinstance(obj,dict) else obj[:20] if isinstance(obj,list) else []
                for item in items:
                    if isinstance(item,dict):
                        for key in item:
                            # No keys that resemble unique IDs, tokens or user details.
                            if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]{0,48}",key) and not re.search(r'id|token|secret|auth|email|name|url|key|session|cookie',key,re.I):
                                json_key_counts[key]+=1
            elif is_sqlite(data):
                with tempfile.TemporaryDirectory(prefix="whoop-cache-") as temp:
                    dbpath=Path(temp)/"cache.sqlite"
                    dbpath.write_bytes(data)
                    db=sqlite3.connect(dbpath.as_uri()+"?mode=ro",uri=True)
                    try:
                        for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table'"):
                            if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]{0,48}",name) and not re.search(r'cookie|token|credential|secret|user|account',name,re.I):
                                cache_db_tables[name]+=1
                    finally: db.close()
        except (ValueError,UnicodeError,sqlite3.DatabaseError,zipfile.BadZipFile,OSError):
            pass
    # Opaque cache reconnaissance, aggregate-only. Avoid logging sensitive
    # content, cache keys, HTTP endpoints or per-file identifiers.
    opaque_magic=collections.Counter()
    opaque_entropy=collections.Counter()
    opaque_text_markers=collections.Counter()
    for entry in files:
        lower=entry.filename.lower()
        if not any(t in lower for t in ("/cache/","/caches/","/cache.db","/cfnetwork/")):
            continue
        if entry.file_size==0: continue
        try:
            with z.open(entry) as source: head=source.read(8192)
            if not head: continue
            if head.startswith(b"SQLite format 3") or head.startswith(b"bplist00") or head.lstrip().startswith((b"{",b"[",b"<?xml")):
                continue
            # Shannon entropy of byte frequencies, bucketed without exposing bytes.
            import math
            counts=collections.Counter(head)
            entropy=-sum((n/len(head))*math.log2(n/len(head)) for n in counts.values())
            bucket="low (<4)" if entropy<4 else "medium (4-6)" if entropy<6 else "high (6-7.5)" if entropy<7.5 else "very-high (>=7.5)"
            opaque_entropy[bucket]+=1
            if head.startswith(bytes.fromhex("1f8b")): kind="gzip"
            elif head.startswith(bytes.fromhex("28b52ffd")): kind="zstd"
            elif head.startswith(bytes.fromhex("04224d18")): kind="lz4"
            elif head.startswith(bytes.fromhex("504b0304")): kind="zip"
            elif head.startswith(b"bplist00"): kind="plist"
            elif head.startswith(b"RIFF"): kind="riff"
            elif head.startswith(bytes.fromhex("789c")) or head.startswith(bytes.fromhex("78da")) or head.startswith(bytes.fromhex("7801")): kind="zlib-candidate"
            elif head.startswith(bytes.fromhex("0a")): kind="protobuf-candidate-unverified"
            else: kind="unknown"
            opaque_magic[kind]+=1
            lower_head=head.lower()
            for label,needle in (("json-token",b"application/json"),("protobuf-token",b"protobuf"),("gzip-token",b"gzip"),("http-header",b"http/1."),("activity-token",b"activity"),("strain-token",b"strain"),("heart-token",b"heart_rate")):
                if needle in lower_head: opaque_text_markers[label]+=1
        except (OSError,ValueError,zipfile.BadZipFile):
            continue
    # Inspect RIFF container types and strain-bearing cache headers only.
    # Report aggregate counts, not paths, payloads, or individual health readings.
    riff_forms=collections.Counter()
    riff_chunk_tags=collections.Counter()
    strain_container_kinds=collections.Counter()
    strain_context_counts=collections.Counter()
    for entry in files:
        lower=entry.filename.lower()
        if not any(t in lower for t in ("/cache/","/caches/","/cache.db","/cfnetwork/")) or entry.file_size==0:
            continue
        try:
            with z.open(entry) as source: head=source.read(65536)
            if head.startswith(b"RIFF") and len(head)>=12:
                form=head[8:12]
                label=form.decode("ascii","replace")
                if re.fullmatch(r"[A-Za-z0-9 ]{4}",label):
                    riff_forms[label]+=1
                else:
                    riff_forms["non-ascii"]+=1
                # RIFF chunk walk; bounded to the header sample, no raw output.
                offset=12
                for _ in range(20):
                    if offset+8>len(head): break
                    tag=head[offset:offset+4]
                    chunk_size=int.from_bytes(head[offset+4:offset+8],"little")
                    if all(32<=b<=126 for b in tag):
                        riff_chunk_tags[tag.decode("ascii")]+=1
                    next_offset=offset+8+chunk_size+(chunk_size&1)
                    if next_offset<=offset or next_offset>len(head): break
                    offset=next_offset
            if b"strain" in head.lower():
                if head.startswith(b"RIFF"): kind="riff"
                elif head.lstrip().startswith((b"{",b"[")): kind="json-like"
                elif head.startswith(b"SQLite format 3"): kind="sqlite"
                elif head.startswith(b"bplist00"): kind="plist"
                else: kind="other"
                strain_container_kinds[kind]+=1
                for label,token in (("json-content-type",b"application/json"),("http",b"http/1."),("activity",b"activity"),("recovery",b"recovery"),("score",b"score"),("heart",b"heart")):
                    if token in head.lower(): strain_context_counts[label]+=1
        except (OSError,ValueError,zipfile.BadZipFile):
            continue
    # Classify strain-bearing non-JSON caches without exposing their content.
    # Detect common HTTP metadata wrappers, plist and compression; summarize
    # size buckets and whether structured JSON occurs after a header prefix.
    strain_wrappers=collections.Counter()
    strain_sizes=collections.Counter()
    strain_json_embedded=collections.Counter()
    for entry in files:
        lower=entry.filename.lower()
        if not any(t in lower for t in ("/cache/","/caches/","/cache.db","/cfnetwork/")) or entry.file_size==0:
            continue
        try:
            with z.open(entry) as source: head=source.read(131072)
            if b"strain" not in head.lower() or head.lstrip().startswith((b"{",b"[")):
                continue
            n=entry.file_size
            strain_sizes["<1KB" if n<1024 else "1-64KB" if n<65536 else "64KB-1MB" if n<1048576 else ">=1MB"]+=1
            if head.startswith(b"bplist00"): wrapper="binary-plist"
            elif head.startswith(b"SQLite format 3"): wrapper="sqlite"
            elif head.startswith(b"RIFF"): wrapper="riff"
            elif head.startswith(bytes.fromhex("1f8b")): wrapper="gzip"
            elif head.startswith(bytes.fromhex("504b0304")): wrapper="zip"
            elif head.startswith(bytes.fromhex("28b52ffd")): wrapper="zstd"
            elif head.startswith(bytes.fromhex("789c")): wrapper="zlib-candidate"
            elif b"HTTP/1." in head[:256]: wrapper="http-response"
            elif b"application/json" in head.lower(): wrapper="http-json-metadata-candidate"
            elif head[:256].count(b"\\x00")>32: wrapper="binary"
            else: wrapper="unclassified"
            strain_wrappers[wrapper]+=1
            # Do not parse or print embedded content. Only indicate if JSON
            # delimiters occur after a non-JSON prefix.
            if b"{" in head or b"[" in head:
                strain_json_embedded["has-json-delimiter"]+=1
            else:
                strain_json_embedded["no-json-delimiter"]+=1
        except (OSError,ValueError,zipfile.BadZipFile):
            continue
    print("CACHE_STRAIN_NONJSON_WRAPPERS",json.dumps(strain_wrappers.most_common()))
    print("CACHE_STRAIN_NONJSON_SIZES",json.dumps(strain_sizes.most_common()))
    print("CACHE_STRAIN_NONJSON_EMBEDDED",json.dumps(strain_json_embedded.most_common()))
    print("CACHE_RIFF_FORMS",json.dumps(riff_forms.most_common(20)))
    print("CACHE_RIFF_CHUNK_TAGS",json.dumps(riff_chunk_tags.most_common(20)))
    print("CACHE_STRAIN_CONTAINER_KINDS",json.dumps(strain_container_kinds.most_common()))
    print("CACHE_STRAIN_CONTEXT",json.dumps(strain_context_counts.most_common()))
    print("CACHE_OPAQUE_MAGIC",json.dumps(opaque_magic.most_common()))
    print("CACHE_OPAQUE_ENTROPY",json.dumps(opaque_entropy.most_common()))
    print("CACHE_OPAQUE_TEXT_MARKERS",json.dumps(opaque_text_markers.most_common()))
    print("CACHE_JSON_PARSED",json_parsed)
    print("CACHE_JSON_FIELD_NAMES",json.dumps(json_key_counts.most_common(35)))
    print("CACHE_SQLITE_TABLE_NAMES",json.dumps(cache_db_tables.most_common(35)))
    print("CACHE_HEADER_FORMATS",json.dumps(cache_signatures.most_common()))
    print("CACHE_SIZE_BUCKETS",json.dumps(cache_size_buckets.most_common()))
    print("CACHE_FILES_INSPECTED",cache_total)
    print("STORAGE_FAMILIES",json.dumps([{"family":k,"files":v,"bytes":family_bytes[k]} for k,v in families.most_common()]))
    print("STORAGE_SIGNATURES",json.dumps([{"extension":k[0],"format":k[1],"count":v} for k,v in signatures.most_common(35)]))
    print("HEALTH_STORAGE_CANDIDATE_FORMATS",json.dumps([{"extension":k[0],"format":k[1],"count":v} for k,v in likely_paths.most_common(20)]))
    interesting=[PurePosixPath(i.filename).name for i in files if re.search(r'heart|activity|sleep|sensor|workout|log',i.filename,re.I)]
    print("RELEVANT_FILE_BASENAMES",json.dumps(interesting[:70]))

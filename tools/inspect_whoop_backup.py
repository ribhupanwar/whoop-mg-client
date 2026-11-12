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
    interesting=[PurePosixPath(i.filename).name for i in files if re.search(r'heart|activity|sleep|sensor|workout|log',i.filename,re.I)]
    print("RELEVANT_FILE_BASENAMES",json.dumps(interesting[:70]))

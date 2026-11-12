#!/usr/bin/env python3
"""Offline, read-only inventory of an iOS WHOOP container ZIP. No raw records printed."""
import collections, io, json, os, re, sqlite3, sys, tempfile, zipfile
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
    for i in dbs[:80]:
        try:
            with z.open(i) as source:
                data=source.read(MAX_FILE+1)
            if not is_sqlite(data): continue
            with tempfile.NamedTemporaryFile(suffix='.sqlite') as tmp:
                tmp.write(data);tmp.flush()
                con=sqlite3.connect('file:'+tmp.name+'?mode=ro',uri=True)
                rows=con.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
                names=[x[0] for x in rows]
                relevant=[n for n in names if re.search(r'heart|pulse|activity|workout|sleep|sample|sensor|biometric|rr|hrv',n,re.I)]
                print("DB",PurePosixPath(i.filename).name,"TABLES",len(names),"RELEVANT",json.dumps(relevant[:50]))
                for name in relevant[:20]:
                    cols=con.execute('PRAGMA table_info("'+name.replace('"','""')+'")').fetchall()
                    print("SCHEMA",name,json.dumps([c[1] for c in cols][:35]))
                con.close()
        except Exception as exc:
            print("DB_ERROR",PurePosixPath(i.filename).suffix,type(exc).__name__)
    interesting=[PurePosixPath(i.filename).name for i in files if re.search(r'heart|activity|sleep|sensor|workout|log',i.filename,re.I)]
    print("RELEVANT_FILE_BASENAMES",json.dumps(interesting[:70]))

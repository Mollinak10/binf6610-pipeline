#!/usr/bin/env python3
"""Load runs of the variant-call pipeline into the SQLite database built by db/schema.sql.

    python3 db/load.py runs.db db/variant-call-cohort.tsv smoke-run-nf cluster-run-nf ...

The first argument is the database, the second the sample metadata, and every other one a
run's folder, holding manifest.json, samples.tsv and variants.tsv. Each run goes in whole or
not at all; a run already in the database is skipped, so loading twice changes nothing.
"""
import csv
import json
import os
import sqlite3
import sys

META_COLUMNS = ["sex", "population", "family", "father", "mother", "phenotype",
                "is_synthetic_phenotype"]


def read_tsv(path):
    """The rows of a tab-separated file as dictionaries; lines starting with # are notes."""
    with open(path, newline="") as f:
        lines = [line for line in f if not line.startswith("#")]
    return list(csv.DictReader(lines, delimiter="\t"))


def number(text, kind):
    """A number from a TSV field, or None for an empty value or '.'."""
    text = (text or "").strip()
    return None if text in ("", ".") else kind(text)


def load_metadata(con, path):
    """Every metadata row into samples, each value as the file writes it."""
    rows = read_tsv(path)
    with con:
        for row in rows:
            con.execute(
                "INSERT INTO samples (sample_id, " + ", ".join(META_COLUMNS) + ")"
                " VALUES (?" + ", ?" * len(META_COLUMNS) + ")"
                " ON CONFLICT (sample_id) DO NOTHING",
                [row["sample_id"]] + [row.get(c, "") for c in META_COLUMNS])
    print(f"samples: {len(rows)} metadata rows")


def pipeline_id(con, p):
    """The pipelines row of this name, version and implementation, made if it is new."""
    key = (p["name"], p["version"], p["implementation"])
    found = con.execute("SELECT pipeline_id FROM pipelines"
                        " WHERE name = ? AND version = ? AND implementation = ?", key).fetchone()
    if found:
        return found[0]
    return con.execute("INSERT INTO pipelines (name, version, implementation) VALUES (?, ?, ?)",
                       key).lastrowid


def load_run(con, folder):
    """One run's folder into runs, run_samples, variants and outputs, in one transaction."""
    with open(os.path.join(folder, "manifest.json")) as f:
        m = json.load(f)
    p, platform, params = m["pipeline"], m.get("platform", {}), m.get("params", {})
    run_id = p["run_id"]

    if con.execute("SELECT 1 FROM runs WHERE run_id = ?", (run_id,)).fetchone():
        print(f"{folder}: run {run_id} is already loaded, skipped")
        return True

    samples = read_tsv(os.path.join(folder, "samples.tsv"))
    variants = read_tsv(os.path.join(folder, "variants.tsv"))
    library = {s["sample_id"]: s.get("library_type") for s in m.get("samples", [])}

    try:
        with con:                    # commits at the end, or undoes the whole run on an error
            pid = pipeline_id(con, p)
            con.execute(
                "INSERT INTO runs (run_id, pipeline_id, git_sha, started_at, finished_at,"
                " exit_status, platform, executor, samplesheet, reference, region, folder)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (run_id, pid, p.get("git_sha"), p["started_at"], p["finished_at"],
                 p.get("exit_status"), platform["kind"],
                 platform.get("executor") or p.get("executor"),
                 params.get("samplesheet"), params.get("ref"), params.get("region"),
                 os.path.abspath(folder)))
            for s in samples:        # a sample the metadata does not list gets an empty row
                con.execute("INSERT INTO samples (sample_id) VALUES (?)"
                            " ON CONFLICT (sample_id) DO NOTHING", (s["sample_id"],))
            for s in samples:        # the key (run_id, sample_id) refuses a sample listed twice
                con.execute("INSERT INTO run_samples (run_id, sample_id, condition, library_type)"
                            " VALUES (?, ?, ?, ?)",
                            (run_id, s["sample_id"], s.get("condition"),
                             library.get(s["sample_id"])))
            con.executemany(
                "INSERT INTO variants (run_id, chrom, pos, ref, alt, qual, filter)"
                " VALUES (?, ?, ?, ?, ?, ?, ?)",
                [(run_id, v["chrom"], number(v["pos"], int), v["ref"], v["alt"],
                  number(v["qual"], float), v["filter"]) for v in variants])
            con.executemany(
                "INSERT INTO outputs (run_id, path, sha256) VALUES (?, ?, ?)",
                [(run_id, o["path"], o["checksum"].lower().replace("sha256:", ""))
                 for o in m.get("outputs", [])])
    except sqlite3.IntegrityError as e:
        print(f"{folder}: run {run_id} refused, nothing of it loaded: {e}", file=sys.stderr)
        return False

    print(f"{folder}: run {run_id} loaded: {len(samples)} samples, {len(variants)} variants,"
          f" {len(m.get('outputs', []))} outputs")
    return True


def main(argv):
    if len(argv) < 3:
        sys.exit("usage: python3 db/load.py <database> <metadata.tsv> <run folder> ...")
    db, metadata, folders = argv[0], argv[1], argv[2:]
    con = sqlite3.connect(db)
    con.execute("PRAGMA foreign_keys = ON")    # SQLite checks the keys only when asked
    load_metadata(con, metadata)
    refused = [f for f in folders if not load_run(con, f)]
    con.close()
    if refused:
        sys.exit(f"{len(refused)} run(s) refused: {', '.join(refused)}")


if __name__ == "__main__":
    main(sys.argv[1:])

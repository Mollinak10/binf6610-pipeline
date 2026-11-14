-- db/schema.sql: one database for every run of the variant-call pipeline.

-- A pipeline version: one row for each name + version + implementation.
CREATE TABLE pipelines (
    pipeline_id     INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    version         TEXT NOT NULL,
    implementation  TEXT NOT NULL,
    UNIQUE (name, version, implementation)
) STRICT;

-- One row for each run: the facts in its manifest.json, and the folder it is in.
CREATE TABLE runs (
    run_id       TEXT PRIMARY KEY,
    pipeline_id  INTEGER NOT NULL REFERENCES pipelines (pipeline_id),
    git_sha      TEXT,
    started_at   TEXT NOT NULL,
    finished_at  TEXT NOT NULL,
    exit_status  TEXT,
    platform     TEXT NOT NULL,
    executor     TEXT,
    samplesheet  TEXT,
    reference    TEXT,
    region       TEXT,
    folder       TEXT NOT NULL
) STRICT;

-- One row for each sample: the metadata file's columns, NULL for a sample it does not list.
CREATE TABLE samples (
    sample_id               TEXT PRIMARY KEY,
    sex                     TEXT,
    population              TEXT,
    family                  TEXT,
    father                  TEXT,
    mother                  TEXT,
    phenotype               TEXT,
    is_synthetic_phenotype  TEXT
) STRICT;

-- Which samples each run used, as that run described them. A sample appears once per run.
CREATE TABLE run_samples (
    run_id        TEXT NOT NULL REFERENCES runs (run_id),
    sample_id     TEXT NOT NULL REFERENCES samples (sample_id),
    condition     TEXT,
    library_type  TEXT,
    PRIMARY KEY (run_id, sample_id)
) STRICT;

-- One row for each line of a run's variants.tsv.
CREATE TABLE variants (
    run_id  TEXT NOT NULL REFERENCES runs (run_id),
    chrom   TEXT NOT NULL,
    pos     INTEGER NOT NULL,
    ref     TEXT NOT NULL,
    alt     TEXT NOT NULL,
    qual    REAL,
    filter  TEXT
) STRICT;
CREATE INDEX variants_by_run ON variants (run_id);

-- One row for each file in the manifest's outputs, with its checksum (the 64 hex characters).
CREATE TABLE outputs (
    run_id  TEXT NOT NULL REFERENCES runs (run_id),
    path    TEXT NOT NULL,
    sha256  TEXT NOT NULL,
    PRIMARY KEY (run_id, path)
) STRICT;

# Troubleshooting log

## Week 3 — four deliberate failures with the container

### Breakage 1: an unpinned recipe, built twice (laptop)

Command: in ~/breakage1, a Dockerfile of `FROM ubuntu` and `RUN apt-get update && apt-get install -y curl`. Built with `docker build -t unpinned:day1 .` on Fri Oct 2 15:13, then rebuilt with `docker build --pull --no-cache -t unpinned:day2 .` on Fri Oct 2 17:02. Each package list taken with `docker run --rm <image> dpkg -l`. Files: troubleshooting/breakage1/ (both dpkg lists, dates, image ids, and dpkg-diff.txt with every line that differs).

The brief asks for a day between the builds; I had 1 h 49 min because of the deadline. I expected no difference over so short a gap. Instead `ubuntu:latest` had moved to a new release in between:

    build 1: FROM ubuntu:latest@sha256:66460d557b25...   image sha256:b1cd44f3...   113 packages, Ubuntu 24.04
    build 2: FROM ubuntu:latest@sha256:3595d7fc4286...   image sha256:6f6336d8...   117 packages, Ubuntu 26.04

Every package line differs (diff `1,113c1,117`). For example: curl 8.5.0-2ubuntu10.15 -> 8.18.0-1ubuntu2.7, libc6 2.39-0ubuntu8.6 -> 2.43-2ubuntu2.4, bash 5.2.21-2ubuntu4 -> 5.3-2ubuntu1, openssl 3.0.13-0ubuntu3.16 -> 3.5.5-1ubuntu3.7, ca-certificates 20260601~24.04.1 -> 20260601~26.04.1, and GNU coreutils 9.4 was replaced by rust-coreutils 0.10.0. The same two-line recipe gave a different operating system. Without --pull and --no-cache the second build would have been a cache hit and looked identical. Fix: a tagged base (here mambaorg/micromamba:2.0.5-ubuntu24.04, recorded by digest in IMAGE.md), =version on every package, and pull the finished image by its digest rather than rebuilding.

### Breakage 2: no --bind (job 10767626)

Command: deleted the `--bind /courses/BINF6610.202710,/scratch/${USER}` line from 01_persample.sbatch, then `sbatch --array=1 01_persample.sbatch` (restored with git checkout). The script Slurm ran (`scontrol write batch_script`) had the --env lines and "${SIF}" but no --bind.

    10767626_1   FAILED   1:0   00:00:04

Output: `ERROR: samplesheet not found: /courses/BINF6610.202710/data/samplesheet-variant8.csv`. It stopped in stage 0, exit code 1, after 4 seconds. The path the container could not see was /courses/BINF6610.202710: without --bind, Apptainer shows only home, /tmp and the current directory. One line earlier the job script, outside the container, had read the same samplesheet with awk to pick NA12878; inside, it did not exist. Fix: keep --bind /courses/BINF6610.202710,/scratch/${USER}.

### Breakage 3: no --env THREADS (job 10767653)

Command: deleted `--env THREADS="${THREADS}"` from 01_persample.sbatch, then `sbatch --array=1 --cpus-per-task=8 01_persample.sbatch` (8 cores, so the default of 4 would show).

    10767653_1   COMPLETED   00:09:58   AllocCPUS 8   TotalCPU 22:21.994

Output: the log said `environment OK: ... THREADS=4`. bwa's log ended `[main] CMD: bwa mem -t 4 ...`, and HaplotypeCaller ran with `--native-pair-hmm-threads 4` (log line 96, with -Djava.io.tmpdir=/tmp/10767653, this job's id). The job held 8 cores and used about 2.2 (22:22 CPU over 9:58), and nothing failed: under --cleanenv THREADS never reached the container, so lib/common.sh fell back to THREADS=${THREADS:-4}. Fix: keep --env THREADS="${THREADS}".

### Breakage 4: an arm64 image on Explorer (srun job 10766653)

Command: `apptainer pull --arch arm64 arm.sif docker://ubuntu:24.04`, then `apptainer exec arm.sif uname -m`, on a compute node.

Output: the pull succeeded (exit code 0, a 28 MB arm.sif, no warning about architecture). The run failed: `FATAL: While checking container encryption: could not open image /scratch/kaul.mo/breakage4/arm.sif: the image's architecture (arm64) could not run on the host's (amd64)`, exit code 255. A wrong-architecture image downloads and converts without complaint and fails only when used. Fix: build with --platform linux/amd64 and check with `docker image inspect --format '{{.Architecture}}'` before pushing.


## Week 2 — four deliberate failures on Explorer

### 1. A --time that is too short (job 10763699)

    10763699_1        TIMEOUT      0:0   00:02:08
    10763699_1.batch  CANCELLED    0:15  00:02:14

Submitted task 1 (NA12878) with --time=00:02:00. Slurm stopped it with State TIMEOUT; the batch step got signal 15. The log stopped in stage 3, right after `bwa mem: NA12878` started: `CANCELLED AT 2026-10-02T14:07:20 DUE TO TIME LIMIT`. On disk, stage 2's trimmed reads had been rewritten (14:06), but 03_align/NA12878.sorted.bam was still the 13:38 file from the earlier complete run, because samtools sort only writes the BAM at the end. The folder held files from two different runs side by side, with nothing to say so.

### 2. One task exits 1, with the cohort job on afterok (array 10763768, cohort 10763770)

    10763768_2   FAILED     1:0   Reason None         00:00:08
    10763770     CANCELLED  0:0   Reason Dependency   00:00:00

I added a temporary line to 01_persample.sbatch so that task 2 exits 1, submitted with ARRAY=2 bash slurm/submit.sh, then restored the file with git checkout. Task 2 FAILED with exit code 1; its log reads `deliberate failure for breakage 2`. The cohort job was CANCELLED with Reason Dependency and ran for 0 seconds: it depends on afterok and was submitted with --kill-on-invalid-dep=yes, so no cohort VCF was built from an incomplete set of samples.

### 3. --array=9 against the eight-row samplesheet (job 10763703)

    10763703_9   FAILED   64:0   00:00:04

Task 9 has no row in the samplesheet, so `awk 'NR == n + 1'` returned an empty sample name. The guard in 01_persample.sbatch refused it before anything ran: the log is one line, `task 9: no row 9 in /courses/BINF6610.202710/data/samplesheet-variant8.csv`, and the exit code is 64. Without that guard, run_sample.sh would have been called with an empty sample_id. My run_sample.sh has a second check (`sample_id is empty`) and would also stop, but a pipeline without either check could select no rows or every row and still finish COMPLETED — more completed tasks than results, with no error.

### 4. scancel mid-run, then resubmit (cancelled 10763818, rerun 10763851)

    10763818_1        CANCELLED+   0:0   00:01:52
    10763818_1.batch  CANCELLED    0:15  00:01:53

I aimed to cancel during fastp, but fastp finished first (stage 2 ran 14:16:42–14:17:20), so the scancel landed during alignment: the log ends `bwa mem: NA12878` then `CANCELLED AT 2026-10-02T14:18:02`. What was left on disk: the trimmed reads were complete (gzip -t on NA12878.R1.trim.fastq.gz passed, same size as before) and NA12878.sorted.bam was still the 13:38 file, so no partial BAM reached /scratch — the half-written sort output was in /tmp/<jobid>, which the trap removes. The rerun (10763851) did not trust what was left behind: its log shows stages 0, 1, 2 (fastp again, new timestamps 14:20) and 3 (bwa mem again) all running from the raw reads, because the pipeline has no skip-if-output-exists logic. That is safe, since a leftover file can never be mistaken for finished work, but it repeats work that had already completed.

## Week 1 — setup problems (Assignment 1)

cd ~/binf6610-pipeline
cat > TROUBLESHOOTING.md <<'EOF'

### 1. Setup commands failed in PowerShell
**Symptom:** The tool-check loop failed with `Missing opening '(' after keyword 'for'` and `The token '||' is not a valid statement separator`.
**Evidence:** The prompt was `PS C:\WINDOWS\system32>`, so the commands were going to Windows PowerShell, which parses a different language from bash.
**Cause:** The pipeline and its commands are bash. Also, bwa, samtools, fastp and GATK from bioconda do not run natively on Windows at all.
**Fix:** Ran everything inside Ubuntu under WSL2 (`wsl -l -v` confirmed VERSION 2). The same loop then printed a path for every tool.

### 2. The conda environment "disappeared"
**Symptom:** After Ubuntu closed and reopened, `conda activate binf6610` gave `EnvironmentNameNotFound`.
**Evidence:** The prompt now read `molly_k@DESKTOP-MBJ0599` instead of `molly@DESKTOP-MBJ0599`. `whoami` returned `molly_k`, and `conda env list` showed only `base` and `molly`, both under `/home/molly_k/miniforge3`.
**Cause:** I was logged in as a different Linux user, which has its own conda install, so the environment created as `molly` did not exist there.
**Fix:** Recreated the environment as `molly_k` and added `unzip` and `git` to it to avoid needing sudo. The tool check then found all eight tools. I now always work as `molly_k`.

### 3. `git remote add` silently never ran
**Symptom:** `git remote add origin https://github.com/<your-github-username>/binf6610-pipeline.git` printed `-bash: your-github-username: No such file or directory`.
**Evidence:** The error names the text inside the angle brackets as if it were a file. Bash reads `<` as input redirection, so it tried to open a file called `your-github-username` and never ran git.
**Cause:** I pasted a placeholder literally instead of replacing it.
**Fix:** Reran the command with my real username (`Mollinak10`). The later push reached the right repository.

### 4. `git push` rejected
**Symptom:** `remote: Invalid username or token. Password authentication is not supported for Git operations.`
**Evidence:** The message says GitHub no longer accepts account passwords over HTTPS. Retrying with a personal access token failed the same way. Nothing appears on screen in the password prompt, and Ctrl+V does not paste in the Ubuntu terminal, so I could not confirm the token actually went in.
**Cause:** GitHub requires a token, and pasting into the hidden prompt was not working.
**Fix:** Installed the GitHub CLI (`conda install -c conda-forge gh`), ran `gh auth login` with browser login, then `gh auth setup-git`. `git push` worked without a password prompt, and the repository page showed my commit.
EOF
cat TROUBLESHOOTING.md


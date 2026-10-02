# Troubleshooting log

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


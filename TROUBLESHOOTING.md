# Troubleshooting log — Assignment 5 (Snakemake)

## 1. Ctrl-C halfway through a smoke run, then the same command

Command: `snakemake --profile profiles/laptop --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb`, stopped with Ctrl-C, then run again unchanged (logs: b1-smk-run2.txt, b1-smk-after.txt, b1-smk-after2.txt, b1-smk-run3.txt, b1-smk-run4.txt).

What it said: the first Ctrl-C landed between jobs, just after fastp for smoke_02 had finished, so nothing was cut off and the same command simply carried on, with 17 of the 21 jobs left. The second Ctrl-C landed while HaplotypeCaller for smoke_02 was running, and the same command then refused to start: `IncompleteFilesException: The files below seem to be incomplete ... To re-generate the files rerun your command with the --rerun-incomplete flag. Incomplete files: work/gvcf/smoke_02.g.vcf.gz`.

Fix: the option it named, `--rerun-incomplete`. With it, 15 jobs ran (HaplotypeCaller for smoke_02 again, `reason: Forced execution`, and everything not yet done); after one more interruption, the last run had 13 jobs and finished: `13 of 13 steps (100%) done`.

## 2. A log without {sample} in the stage-3 rule

Command: changed bwa_mem's `log:` to `"logs/bwa_mem.log"` and ran `snakemake --profile profiles/laptop -n --config ...` (log: b2-smk.txt).

Error: `RuleException in file "Snakefile", line 142: Not all output, log and benchmark files of rule bwa_mem contain the same wildcards. This is crucial though, in order to avoid that two or more jobs write to the same file.`

Why: bwa_mem runs once per sample, so its output has {sample}; a log without {sample} would be the same file for all three jobs, and they would overwrite each other's logs. Snakemake refuses before anything runs. Fix: put `{sample}` back, `"logs/bwa_mem/{sample}.log"`.

## 3. No wildcard_constraints in the two stage-2 rules

Command: deleted both `wildcard_constraints:` blocks from fastp_paired and fastp_single and ran `snakemake --profile profiles/laptop -n --config ...` (log: b3-smk.txt).

Exception: `AmbiguousRuleException: Rules fastp_paired and fastp_single are ambiguous for the file work/trim/smoke_01_R1.trim.fastq.gz.` Both rules make a file of that name, so without the constraints both match every sample, and Snakemake cannot choose. Fix: put back `sample=one_of(PAIRED)` and `sample=one_of(SINGLE)`, so each sample matches exactly one rule.

## 4. No Apptainer on the first Explorer run

Command: deleted `software-deployment-method: apptainer` from profiles/explorer/profile.yaml and ran `sbatch slurm/snakemake.sbatch` (head job 11153886).

Output: validate finished (`Finished jobid: 7 (Rule: validate)`), then fastp_paired failed for every paired sample (`Error in rule fastp_paired: (command exited with non-zero exit code)`), and the head job stopped: `WorkflowError: At least one job did not complete successfully.` The job's own Slurm log, .snakemake/slurm_logs/rule_fastp_paired/NA12878/11153937.log (b4-smk-slurmlog.txt), says only that the command exited with a non-zero exit code. The rule's own log, logs/fastp/NA12878.log (b4-smk-rulelog.txt), gives the cause: `/usr/bin/bash: line 1: fastp: command not found`, bash's exit status 127. Without Apptainer the rule ran directly on the compute node, which has no fastp. validate worked because it needs only bash, gzip and awk.

Fix: put the line back and submit the same head job again. `snakemake -n` (b4-smk-dryrun.txt) showed that validate, which had finished, would run again, with the reason `software environment definition has changed since last execution`: it had run without an image, and now runs in one.

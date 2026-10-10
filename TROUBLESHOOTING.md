# Troubleshooting log — Assignment 4

## 1. Ctrl-C halfway through a smoke run, then -resume

Command: `nextflow run main.nf -profile docker -ansi-log false --samplesheet ~/smoke/samplesheet.csv --ref ~/smoke/smoke.fa --region smoke_1mb --outdir results-b1`, stopped with Ctrl-C just after `[27/b24fdf] Submitted process > MARKDUPLICATES (smoke_01)`, then the same command with `-resume` (logs: b1-run1.txt, b1-run2.txt).

Output: 10 tasks were cached, with the same hashes as the first run: VALIDATE, FASTQC x3, FASTP x3 and BWA_MEM x3 (for example `[d3/16d2c7] Cached process > BWA_MEM (smoke_01)`). MARKDUPLICATES (smoke_01), which Ctrl-C interrupted, ran again in a new work folder (2f/56222e instead of 27/b24fdf), and so did everything downstream of it: MARKDUPLICATES x3, HAPLOTYPECALLER x3, JOINT_GENOTYPE, FILTER, MULTIQC and PUBLISH. Fix: none needed; -resume reuses every task that finished with unchanged inputs and script, and reruns only the unfinished ones.


## 2. The reference as a queue channel in the stage-3 call

Command: changed main.nf to `BWA_MEM(FASTP.out.reads, channel.fromPath(params.ref), ref_index)`, ran the smoke dataset with `--outdir results-b2` (log: b2-run.txt), then restored main.nf with git checkout.

Output: BWA_MEM ran for one sample only, `[19/d69b73] Submitted process > BWA_MEM (smoke_03)`, out of three. Nothing stopped the run: it continued with one MARKDUPLICATES and one HAPLOTYPECALLER, then JOINT_GENOTYPE, FILTER, MULTIQC and PUBLISH, and published a "cohort" VCF. A queue channel holds one item, the reference, and the first sample used it up, so the other two never ran, with no error. Fix: give the reference as a value channel, `ref = file(params.ref)`, so every sample gets it.
The VCF's sample columns in results-b2/cohort.filtered.vcf.gz: smoke_03

## 3. A $(...) without its backslash in a script block

Command: added `echo "fastqs here: $(ls *.fastq.gz | wc -l)" >&2` to VALIDATE's script block in modules/validate.nf, without the backslash before the $, and ran the smoke dataset (log: b3-run.txt). Restored with git checkout.

Output: VALIDATE failed with exit status 1. The task's .command.sh, read from work/10/260e320cec18907ee383a5b4042623, was already wrong: Nextflow had written `echo "fastqs here: samplesheet.csvls *.fastq.gz | wc -l)" >&2` and `validate_samplesheet.sh smoke.dict`. Groovy took the unescaped $ as its own and spliced into the echo the file names meant for the next line, so bash never saw $(...), and validate_samplesheet.sh got one argument instead of three. .command.err: `validate_samplesheet.sh: line 5: 2: usage`. Running `bash .command.run` in the work folder gave the same error and exit 1: the script itself was broken before bash ran. Fix: write every bash $ in a script block as \$, here `\$(ls *.fastq.gz | wc -l)`.

## 4. A two-minute time limit for HAPLOTYPECALLER on the first Explorer run

Command: on the first Explorer run, `-c b4.config` added `process { withName: 'HAPLOTYPECALLER' { time = '2m' } }` to the explorer profile (head job 10957273). Then I submitted slurm/nextflow.sbatch again, without it, so HAPLOTYPECALLER had its 1h limit back (head job 10967887).

Output: Nextflow reported `Process HAPLOTYPECALLER (NA10851) terminated with an error exit status (140)`. In sacct (b4-sacct.txt), two HaplotypeCaller jobs are FAILED with ExitCode 12:0, Elapsed 00:01:19 and 00:01:01, and Timelimit 00:02:00; the other six are CANCELLED, killed by Nextflow after the first failure (`WARN: Killing running tasks`). Not TIMEOUT: Nextflow asks Slurm to signal it before the limit and stops the task itself when the signal comes, so the jobs ended at about a minute with signal 12 (SIGUSR2), which Nextflow reports as 140 = 128 + 12. Fix: put the 1h limit back and resubmit; -resume reused VALIDATE, FASTQC, FASTP, BWA_MEM and MARKDUPLICATES for all eight samples and carried on from HaplotypeCaller.

Before that, the first Explorer attempts stopped twice for reasons outside the pipeline: an image conversion failed (`FATAL: ... no descriptor found for reference`, while two images were being converted at once), and once sbatch itself failed (`sbatch: fatal: Unable to process configuration file`). Each time, resubmitting with -resume carried on from the finished tasks.

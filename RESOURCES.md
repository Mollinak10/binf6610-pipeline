# Resources — Assignment 2

Real run: array 10763261 (8 tasks), cohort 10763269. Both COMPLETED.

| Job | Asked for first | Measured (seff / sacct / memory.peak) | Set to now | Why |
|---|---|---|---|---|
| per-sample | 8 CPU, 16G, 1:00:00 | 5:01–11:10 wall; ~3.1 of 8 cores busy (seff CPU Efficiency 38.77% on the slowest task); memory.peak 6.96–8.42 GB | 4 CPU, 16G, 0:30:00 | Cores: see comparison below. Memory: 16G is ~1.9x the 8.42 GB peak, a safe margin, so kept. Time: longest task 11:10, so 30 min is ~2.7x |
| cohort | 4 CPU, 16G, 1:00:00 | 7:20 wall; ~1.1 of 4 cores busy (seff CPU Efficiency 27.95%); memory.peak 1.31 GB (seff Memory Efficiency 7.58% of 16 GB) | 2 CPU, 8G, 0:30:00 | Reduced: it used about one core and 1.3 GB. 8G rather than 4G because the JVM heap is allowed up to 6 GB (JAVA_MEM=6g) |

## Core-count comparison (same sample, task 3)

| --cpus-per-task | Wall-clock | CPU time (sacct TotalCPU) | Cores busy | Core-minutes |
|---|---|---|---|---|
| 2 (job 10763693) | 7:41 | 10:31 | 1.4 | 15.4 |
| 4 (job 10763695) | 6:41 | 13:01 | 1.9 | 26.7 |
| 8 (real run, 10763261_3) | 5:01 | 13:13 | 2.6 | 40.1 |

The 8-core figure comes from the real run, where the task shared nodes with the other seven, so conditions were not identical to the 2- and 4-core runs.

## Raw output

    seff 10763261_7   (slowest per-sample task)
    CPU Utilized: 00:34:38
    CPU Efficiency: 38.77% of 01:29:20 core-walltime
    Job Wall-clock time: 00:11:10
    Memory Utilized: 7.52 GB
    Memory Efficiency: 46.98% of 16.00 GB

    seff 10763269     (cohort job)
    CPU Utilized: 00:08:12
    CPU Efficiency: 27.95% of 00:29:20 core-walltime
    Job Wall-clock time: 00:07:20
    Memory Utilized: 1.21 GB
    Memory Efficiency: 7.58% of 16.00 GB

    sacct MaxRSS (.batch steps): per-sample 6194652K to 7881748K; cohort 1272268K
    memory.peak (bytes): per-sample 6959497216 to 8417890304; cohort 1313812480

## Decision

I changed --cpus-per-task from 8 to 4 for the per-sample job. Going from 4 to 8 cores saved 1:40 per sample, but the job never kept more than about 2.6 cores busy, so 8 cores cost 50% more core-minutes (40.1 vs 26.7) for a 25% speed-up, and the whole array is held up by its slowest sample (11:10) anyway. I reduced the cohort job to 2 CPUs and 8G because seff showed it using about 1 core and 1.3 GB of the 16 GB it asked for. I lowered both time limits to 30 minutes, about 2.7x and 4x the longest measured runs.

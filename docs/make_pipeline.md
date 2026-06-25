# Standalone Mapping with GNU Make

The `scripts/Makefile` is a single-sample alignment workflow that runs the same steps as the Nextflow pipeline without requiring Nextflow, SLURM, or containers. It is useful for testing a single sample, debugging a failed step, or running on a workstation where the full cluster pipeline is not needed.

It implements the same step order: FASTQ concatenation, adapter trimming, BWA alignment, coordinate sorting, duplicate marking, and CRAM conversion.

## Requirements

The following tools must be available on your PATH:

- bwa 0.7.x
- samtools 1.x
- picard
- trim_galore
- GNU make 4.3 or later

## Reference Preparation

You need a GRCh38 reference FASTA with BWA index files and a samtools faidx index built alongside it. If you have already run `make index` from the `nf-igsr-wgs/` directory, these files exist at:

```
../reference/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna
../reference/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.amb
../reference/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.ann
../reference/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.bwt
../reference/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.fai
../reference/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.pac
../reference/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.sa
```

If the BWA index files are missing, the Makefile will build them automatically before alignment. This takes around 90 minutes for GRCh38.

## Parameters

All parameters have defaults and are passed on the command line as `KEY=VALUE`.

| Parameter | Default | Description |
|-----------|---------|-------------|
| SAMPLE | required | Sample name, used to name all output files |
| FASTQ_DIR | required | Directory containing paired FASTQ files |
| REF | required | Path to reference FASTA |
| OUTDIR | results | Output directory |
| THREADS | 16 | CPU threads for BWA, samtools sort, and CRAM conversion |
| SORT_MEM | 4 | Memory per thread for samtools sort (GB) |
| JVM_MEM | 28 | JVM heap size for Picard (GB) |

The FASTQ_DIR must contain files matching `*_1.fastq.gz` and `*_2.fastq.gz`. Multiple files per direction are concatenated automatically before trimming.

## Running

Run from the `nf-igsr-wgs/` directory:

```bash
make -f scripts/Makefile \
    SAMPLE=HG00320 \
    FASTQ_DIR=/path/to/HG00320/fastqs \
    REF=/path/to/reference/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna
```

To change the output directory or adjust compute resources:

```bash
make -f scripts/Makefile \
    SAMPLE=HG00320 \
    FASTQ_DIR=/path/to/fastqs \
    REF=/path/to/reference.fa \
    OUTDIR=/scratch/results \
    THREADS=32 \
    SORT_MEM=6 \
    JVM_MEM=56
```

## Resume Behaviour

Make checks whether each output file already exists before running its step. If a run is interrupted, re-running the same command resumes from where it left off. No flags or caches are needed.

For example, if `HG00320_sorted.bam` already exists when you re-run, Make skips concatenation, trimming, and alignment and picks up from duplicate marking.

Similarly, if the BWA index files are already present at the reference path, `bwa index` is skipped entirely.

## Output Structure

```
results/
└── HG00320/
    ├── HG00320.cram
    ├── HG00320.cram.crai
    ├── fastqc/
    │   ├── *_fastqc.html
    │   └── *_fastqc.zip
    ├── trim_galore/
    │   └── *_trimming_report.txt
    └── qc/
        ├── HG00320_dedup_metrics.txt
        └── HG00320_flagstat.txt
```

Intermediate BAM files are written to the working directory. They are not removed automatically on completion. To clean them up:

```bash
make -f scripts/Makefile SAMPLE=HG00320 clean
```

This removes the concatenated FASTQs, trimmed FASTQs, and all intermediate BAMs. The CRAM outputs in `OUTDIR` are preserved.

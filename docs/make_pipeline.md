# Standalone Mapping with GNU Make

The `scripts/Makefile` is the single entry point for reference setup and single-sample alignment without Nextflow, SLURM, or containers. It is useful for testing a single sample, debugging a failed step, or running on a workstation where the full cluster pipeline is not needed.

It runs the same steps in the same order as the Nextflow pipeline.

## Requirements

The following tools must be available on your PATH:

- bwa 0.7.x
- samtools 1.x
- picard
- trim_galore
- GNU make 4.3 or later

## Targets

All targets are run from the `nf-igsr-wgs/` directory as `make -f scripts/Makefile <target> [parameters]`.

| Target | What it does | Parameters |
|--------|-------------|------------|
| `download_reference` | Download GRCh38 FASTA and ALT file | REF_DIR (optional) |
| `index` | Build samtools faidx and BWA index | REF (required) |
| `analyse` | Run the full alignment workflow | SAMPLE, FASTQ_DIR, REF (all required) |
| `clean` | Remove intermediate BAM and FASTQ files | SAMPLE (required) |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| REF_DIR | reference | Directory where the reference FASTA is downloaded |
| SAMPLE | required | Sample name, used to name all output files |
| FASTQ_DIR | required | Directory containing paired FASTQ files |
| REF | required | Path to reference FASTA (for `index` and `analyse`) |
| OUTDIR | results | Output directory |
| THREADS | 16 | CPU threads for BWA, samtools sort, and CRAM conversion |
| SORT_MEM | 4 | Memory per thread for samtools sort (GB) |
| JVM_MEM | 28 | JVM heap size for Picard (GB) |

`FASTQ_DIR` must contain files matching `*_1.fastq.gz` and `*_2.fastq.gz`. Multiple files per direction are concatenated automatically before trimming.

## Reference Setup (one-time)

`download_reference` and `index` are setup steps that need to be run once before any samples are analysed. They are not triggered automatically by `analyse` — if the reference or index files are missing when you run `analyse`, BWA will fail.

Both targets have resume behaviour. If the FASTA or index files already exist on disk, Make skips those steps without re-running them.

**Using the 1000 Genomes reference**

`download_reference` fetches the GRCh38 1000G reference into `reference/` by default:

```bash
make -f scripts/Makefile download_reference
make -f scripts/Makefile index REF=reference/GRCh38_full_analysis_set_plus_decoy_hla.fa
```

To download into a different directory:

```bash
make -f scripts/Makefile download_reference REF_DIR=/data/reference
make -f scripts/Makefile index REF=/data/reference/GRCh38_full_analysis_set_plus_decoy_hla.fa
```

**Using your own reference**

`index` works with any FASTA. If you already have a reference, skip `download_reference` and run `index` directly:

```bash
make -f scripts/Makefile index REF=/path/to/your/reference.fa
```

If your reference is already indexed, skip both steps and pass `REF` directly to `analyse`.

## Running the Alignment

```bash
make -f scripts/Makefile analyse \
    SAMPLE=HG00320 \
    FASTQ_DIR=/path/to/HG00320/fastqs \
    REF=../reference/GRCh38.fa
```

To adjust compute resources or the output directory:

```bash
make -f scripts/Makefile analyse \
    SAMPLE=HG00320 \
    FASTQ_DIR=/path/to/fastqs \
    REF=../reference/GRCh38.fa \
    OUTDIR=/scratch/results \
    THREADS=32 \
    SORT_MEM=6 \
    JVM_MEM=56
```

## Resume Behaviour

Make checks whether each output file already exists before running its step. If a run is interrupted, re-running the same command resumes from where it left off. No flags or caches are needed.

For example, if `HG00320_sorted.bam` already exists when you re-run, Make skips concatenation, trimming, and alignment and picks up from duplicate marking. If the BWA index files are already present, `bwa index` is skipped entirely.

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

Intermediate BAM files are written to the working directory and are not removed automatically. To clean them up:

```bash
make -f scripts/Makefile clean SAMPLE=HG00320
```

This removes the concatenated FASTQs, trimmed FASTQs, and all intermediate BAMs. The CRAM outputs in `OUTDIR` are preserved.

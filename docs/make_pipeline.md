# Make Pipeline

The `scripts/Makefile` is a lightweight pipeline for aligning a single Illumina paired-end sequencing sample (WGS or WES) to GRCh38. It performs adapter trimming, BWA-MEM alignment, coordinate sorting, duplicate marking, and CRAM conversion — the same steps in the same order as the Nextflow pipeline, but without requiring Nextflow, SLURM, or containers. It is suitable for testing a single sample, debugging a failed step, or running on a workstation outside the cluster environment.

## Requirements

The following tools must be available on your PATH:

- bwa 0.7.x
- samtools 1.x
- picard
- trim_galore
- multiqc
- GNU make 4.3 or later

## Targets

All targets are run from the `nf-igsr-wgs/` directory as `make -f scripts/Makefile <target> [parameters]`.

| Target | What it does |
|--------|-------------|
| `download_reference` | Download GRCh38 FASTA and ALT file |
| `index` | Build samtools faidx and BWA index |
| `analyse` | Run the full alignment workflow including MultiQC |
| `clean_temp_files` | Remove `intermediate_files/` for SAMPLE |
| `clean` | Remove all output for SAMPLE |

## Parameters

Parameters are passed on the command line as `KEY=value`. Each has a sensible default where applicable; required parameters have no default and must always be supplied.

### Reference setup

| Parameter | Default | Used by | Description |
|-----------|---------|---------|-------------|
| REF_DIR | `reference` | `download_reference` | Directory to download the 1000G reference FASTA into |
| REF | required | `index`, `analyse` | Path to the reference FASTA |

### Alignment

| Parameter | Default | Description |
|-----------|---------|-------------|
| SAMPLE | required | Sample name, used to name all output files and directories |
| FASTQ_DIR | required | Directory containing paired FASTQ files matching `*_1.fastq.gz` and `*_2.fastq.gz` |
| OUTDIR | `results` | Root output directory; all sample output is written to `OUTDIR/SAMPLE/` |
| THREADS | all available CPUs (`nproc`) | Thread count passed to BWA-MEM, samtools sort, and samtools view |
| SORT_MEM | auto | Memory per sort thread in GB. Calculated as `int((total_ram - 8) / THREADS)`, floored at 1. The 8 GB reserve is for OS and samtools I/O overhead |
| JVM_MEM | auto | Picard JVM heap size in GB. Calculated as `total_ram - 8`, floored at 4 |

SORT_MEM and JVM_MEM are derived from the physical RAM detected at make startup via `free -g`. On a 32 GB machine with 4 threads: SORT_MEM = (32−8)/4 = 6, JVM_MEM = 32−8 = 24. Both can be overridden freely:

```bash
make -f scripts/Makefile analyse ... THREADS=8 SORT_MEM=6 JVM_MEM=48
```

### Cleaning

| Parameter | Used by | Description |
|-----------|---------|-------------|
| SAMPLE | `clean_temp_files`, `clean` | Identifies which sample directory to remove |

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

`FASTQ_DIR` must contain files matching `*_1.fastq.gz` and `*_2.fastq.gz`. Multiple files per direction (e.g. multiple sequencing runs for the same sample) are concatenated automatically before trimming. If no matching files are found, the pipeline will fail at the concatenation step.

```bash
make -f scripts/Makefile analyse \
    SAMPLE=HG00320 \
    FASTQ_DIR=/data/HG00320 \
    REF=/data/reference/GRCh38_full_analysis_set_plus_decoy_hla.fa
```

To override compute resources or the output directory:

```bash
make -f scripts/Makefile analyse \
    SAMPLE=HG00320 \
    FASTQ_DIR=/data/HG00320 \
    REF=/data/reference/GRCh38_full_analysis_set_plus_decoy_hla.fa \
    OUTDIR=/scratch/results \
    THREADS=16 \
    SORT_MEM=8 \
    JVM_MEM=56
```

## Resume Behaviour

Make checks whether each output file already exists before running its step. If a run is interrupted, re-running the same command resumes from where it left off. No flags or caches are needed.

Intermediate files are tracked inside `OUTDIR/SAMPLE/intermediate_files/`. For example, if `intermediate_files/HG00320_sorted.bam` already exists when you re-run, Make skips concatenation, trimming, and alignment and picks up from duplicate marking. If the BWA index files are already present, `bwa index` is skipped entirely.

## Output Structure

```
results/
└── HG00320/
    ├── cram/
    │   ├── HG00320.cram
    │   └── HG00320.cram.crai
    ├── alignment_stats/
    │   ├── HG00320_dedup_metrics.txt
    │   └── HG00320_flagstat.txt
    ├── fastqc/
    │   ├── *_fastqc.html
    │   └── *_fastqc.zip
    ├── trim_galore/
    │   ├── *_trimming_report.txt
    │   └── *_trimming_report.json
    ├── multiqc/
    │   └── multiqc_report.html
    ├── logs/
    │   ├── HG00320_trim_galore.log
    │   ├── HG00320_bwa.log
    │   ├── HG00320_markdup.log
    │   └── HG00320_multiqc.log
    └── intermediate_files/
        └── (intermediate FASTQs and BAMs)
```

All intermediate files are written to `intermediate_files/` inside the sample output directory, keeping the repository and calling directory clean. Logs for each step are written to `logs/` with the sample name as a prefix. To remove intermediate files once the run is complete:

```bash
make -f scripts/Makefile clean_temp_files SAMPLE=HG00320
```

This removes only `intermediate_files/`. The CRAM, alignment stats, and MultiQC outputs are preserved. To remove everything for a sample:

```bash
make -f scripts/Makefile clean SAMPLE=HG00320
```

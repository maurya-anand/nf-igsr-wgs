# nf-igsr-wgs

A Nextflow DSL2 pipeline to map 1000 Genomes high-coverage WGS samples to the GRCh38 reference genome and generate coordinate-sorted, duplicate-marked CRAM files.

> [!NOTE]
> This pipeline processes samples from the 1000 Genomes Project 30x high-coverage data collection. More details about this collection can be found on the [IGSR Data Portal](https://www.internationalgenome.org/data-portal/data-collection/1000genomes_30x).
>
> The alignment and post-processing methodology is adapted from the [NYGC b38 pipeline description](https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/data_collections/1000G_2504_high_coverage/20190405_NYGC_b38_pipeline_description.pdf). It implements the workflow described in:
>
> Byrska-Bishop M, Evani US, Zhao X, et al. *High-coverage whole-genome sequencing of the diverse 1000 Genomes Project cohort.* **Cell** 185, 3426–3440 (2022). <https://doi.org/10.1016/j.cell.2022.08.004>
>
> In accordance with these standards, the pipeline performs ALT-aware mapping using BWA-MEM and deduplication with Picard. To optimize performance, GATK Base Quality Score Recalibration has been omitted.

## Requirements

- Nextflow **≥ 26.04.0**
- Singularity / Apptainer or Docker (or compatible container runtime)

## Quick Start

### 1. Prepare your sample sheet (CSV)

`samplesheet.csv`

```csv
sample,run,fastq_1,fastq_2
HG00100,ERR245024,/path/to/ERR245024_1.fastq.gz,/path/to/ERR245024_2.fastq.gz
HG00100,ERR245028,/path/to/ERR245028_1.fastq.gz,/path/to/ERR245028_2.fastq.gz
```

### 2. Download reference data

To download the reference genome assembly and HLA ALT index files, run:

```bash
make reference
```

Expected output:

```bash
../reference/
├── GRCh38_full_analysis_set_plus_decoy_hla.fa
└── GRCh38_full_analysis_set_plus_decoy_hla.fa.alt
```

The indices can be built locally using `make index` or `make index-singularity`. Alternatively, the Nextflow pipeline will run the indexing tasks on your cluster as part of the workflow execution.

### 3. Set pipeline parameters

Configure parameters directly on the command line or within a custom configuration file.

```groovy
params {
    sample_sheet = null
    reference_fa = null
    outdir       = "results"
}
```

### 4. Run the pipeline

```bash
nextflow run main.nf \
  --sample_sheet samplesheet.csv \
  --reference_fa ../reference/GRCh38_full_analysis_set_plus_decoy_hla.fa \
  --outdir alignment-results \
  -profile slurm,singularity
```

## Workflow Overview

The pipeline consists of the following main steps:

- Genome index generation (BWA_INDEX / SAMTOOLS_FAIDX)
  - Builds BWA indices and faidx indices for the GRCh38 reference genome assembly.
  - Executed only if indices are missing.
  - Output: `../reference/GRCh38_full_analysis_set_plus_decoy_hla.fa.*`

- Concatenate FASTQ (CONCAT_FASTQ)
  - Merges multiple lane/run FASTQ files for the same sample by concatenating the raw gzip files.
  - Output: `${sample_id}_1.fastq.gz`, `${sample_id}_2.fastq.gz`

- Adapter removal (ADAPTER_TRIM)
  - Trims adapter sequences from the reads using `trim_galore` with Cutadapt and FastQC.
  - Output: trimmed reads and FastQC report.

- Alignment and sorting (ALIGN_AND_SORT)
  - Aligns trimmed reads using ALT-aware `bwa mem`.
  - Pipes alignments directly to `samtools sort` to avoid writing intermediate BAMs.
  - Keeps temporary sort files in the execution directory to protect system `/tmp` partitions.
  - Output: `${sample_id}_sorted.bam`

- Duplicate marking and CRAM conversion (MARK_DUPLICATES_AND_CRAM)
  - Identifies duplicate molecules using `picard MarkDuplicates`.
  - Converts alignments to CRAM using `samtools view`.
  - Indexing CRAM and calculating metrics using `samtools flagstat`.
  - Output: `${sample_id}.cram`, `${sample_id}.cram.crai`, `${sample_id}_flagstat.txt`, and `${sample_id}_dedup_metrics.txt`

- Summary (MULTIQC)
  - Aggregates QC reports from Trim Galore, FastQC, Picard MarkDuplicates, and Samtools flagstat.
  - Output: `multiqc_report.html`

## Customization

Resource requirements, containers, and execution profiles can be adjusted in:

- `nextflow.config`
- `conf/base.config`
- `conf/slurm.config`

## Components

Tools:

| Component   | Version |
|-------------|---------|
| BWA         | 0.7.19  |
| SAMTOOLS    | 1.23.1  |
| PICARD      | 3.4.0   |
| trim-galore | 2.2.0   |
| multiqc     | 1.35    |

Container Images:

- `community.wave.seqera.io/library/bwa:0.7.19--f40bc2b40f6d8142`
- `community.wave.seqera.io/library/samtools:1.23.1--4a697684755218e0`
- `community.wave.seqera.io/library/trim-galore:2.2.0--7c4d34af422b845e`
- `community.wave.seqera.io/library/bwa_picard_samtools:83e2dd7945f17b8f`
- `community.wave.seqera.io/library/multiqc:1.35--1ad1ebcf6f617695`

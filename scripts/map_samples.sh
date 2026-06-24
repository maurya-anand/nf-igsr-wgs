#!/bin/bash

set -e

REF_DIR="references"
REF="${REF_DIR}/GRCh38_full_analysis_set_plus_decoy_hla.fa"
FASTQ_DIR="fastq"
SAMPLE="HG00100"

cat ${FASTQ_DIR}/*_1.fastq.gz > "${SAMPLE}_combined_1.fastq.gz"
cat ${FASTQ_DIR}/*_2.fastq.gz > "${SAMPLE}_combined_2.fastq.gz"

rg_string="@RG\\tID:${SAMPLE}\\tPL:ILLUMINA\\tSM:${SAMPLE}\\tLB:${SAMPLE}_lib"
bwa mem -Y -K 100000000 -t 16 -R "${rg_string}" "${REF}" "${SAMPLE}_combined_1.fastq.gz" "${SAMPLE}_combined_2.fastq.gz" | \
samtools sort -@ 4 -m 4G -T "$PWD/${SAMPLE}_tmp" -o "${SAMPLE}_sorted.bam" -

picard MarkDuplicates \
    MAX_RECORDS_IN_RAM=2000000 \
    VALIDATION_STRINGENCY=SILENT \
    I="${SAMPLE}_sorted.bam" \
    O=dedup.bam \
    M="${SAMPLE}_dedup_metrics.txt"

samtools view -C -T "${REF}" -o "${SAMPLE}.cram" dedup.bam
samtools index "${SAMPLE}.cram"
samtools flagstat "${SAMPLE}.cram" > "${SAMPLE}_flagstat.txt"

rm -f "${SAMPLE}_combined_1.fastq.gz" "${SAMPLE}_combined_2.fastq.gz" "${SAMPLE}_sorted.bam" dedup.bam

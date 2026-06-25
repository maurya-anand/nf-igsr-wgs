nextflow.enable.dsl = 2


process BWA_INDEX {
    tag "${fasta.name}"
    container 'community.wave.seqera.io/library/bwa_samtools:cf87be72f0989a57'

    input:
    path fasta

    output:
    path "${fasta}.*"

    script:
    """
    set -euo pipefail
    bwa index ${fasta}
    """
}

process SAMTOOLS_FAIDX {
    tag "${fasta.name}"
    container 'community.wave.seqera.io/library/bwa_samtools:cf87be72f0989a57'

    input:
    path fasta

    output:
    path "${fasta}.fai"

    script:
    """
    set -euo pipefail
    samtools faidx ${fasta}
    """
}

process CONCAT_FASTQ {
    tag "${meta.sampleid}"
    container 'community.wave.seqera.io/library/bwa_samtools:cf87be72f0989a57'

    input:
    tuple val(meta), path(fqs_1), path(fqs_2)

    output:
    tuple val(meta), path("${meta.sampleid}_1.fastq.gz"), path("${meta.sampleid}_2.fastq.gz")

    script:
    def fq1_list = fqs_1 instanceof List ? fqs_1.sort().join(' ') : fqs_1
    def fq2_list = fqs_2 instanceof List ? fqs_2.sort().join(' ') : fqs_2
    """
    set -euo pipefail
    cat ${fq1_list} > ${meta.sampleid}_1.fastq.gz
    cat ${fq2_list} > ${meta.sampleid}_2.fastq.gz
    """
}

process ADAPTER_TRIM {
    tag "$meta.sampleid"
    container 'community.wave.seqera.io/library/trim-galore:2.2.0--7c4d34af422b845e'

    publishDir { "${params.outdir}/${meta.sampleid}/fastqc" }, mode: 'copy', pattern: "*_fastqc.{zip,html}"
    publishDir { "${params.outdir}/${meta.sampleid}/trim_galore" }, mode: 'copy', pattern: "*trimming_report.txt"

    input:
    tuple val(meta), path(fastq_1), path(fastq_2)

    output:
    tuple val(meta), path("${meta.sampleid}_1_trimmed.fq.gz"), path("${meta.sampleid}_2_trimmed.fq.gz"), emit: reads
    path "*_fastqc.{zip,html}", emit: fastqc
    path "*_trimming_report.txt", emit: log

    script:
    def fq1_base = fastq_1.toString().tokenize('.')[0]
    def fq2_base = fastq_2.toString().tokenize('.')[0]
    """
    set -euo pipefail
    export TMPDIR=\$PWD
    total_threads=${task.cpus}
    trim_galore \
        --paired \
        --illumina \
        --fastqc \
        --cores \${total_threads} \
        ${fastq_1} ${fastq_2}
    mv ${fq1_base}_val_1.fq.gz ${meta.sampleid}_1_trimmed.fq.gz
    mv ${fq2_base}_val_2.fq.gz ${meta.sampleid}_2_trimmed.fq.gz
    mv ${fastq_1}_trimming_report.txt ${meta.sampleid}_1_trimming_report.txt
    mv ${fastq_2}_trimming_report.txt ${meta.sampleid}_2_trimming_report.txt
    """
}

process BWA_ALIGN {
    tag "${meta.sampleid}"
    container 'community.wave.seqera.io/library/bwa_samtools:cf87be72f0989a57'

    input:
    tuple val(meta), path(fastq_1), path(fastq_2)
    path reference_fa
    path bwa_indices
    path ref_alt

    output:
    tuple val(meta), path("${meta.sampleid}.bam")

    script:
    def rg_string = "@RG\\tID:${meta.sampleid}\\tPL:ILLUMINA\\tSM:${meta.sampleid}\\tLB:${meta.sampleid}_lib"
    """
    set -euo pipefail
    bwa mem -Y -K 100000000 -t ${task.cpus} -R "${rg_string}" ${reference_fa} ${fastq_1} ${fastq_2} | \
    samtools view -@ ${task.cpus} -b -o ${meta.sampleid}.bam -
    """
}

process SAMTOOLS_SORT {
    tag "${meta.sampleid}"
    container 'community.wave.seqera.io/library/bwa_samtools:cf87be72f0989a57'

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.sampleid}_sorted.bam")

    script:
    def sort_mem = task.memory ? ((task.memory.giga - 4) / task.cpus) as int : 4
    """
    set -euo pipefail
    samtools sort -@ ${task.cpus} -m ${sort_mem}G -T \$PWD/${meta.sampleid}_tmp -o ${meta.sampleid}_sorted.bam ${bam}
    """
}

process MARK_DUPLICATES {
    tag "${meta.sampleid}"
    container 'community.wave.seqera.io/library/picard:3.4.0--a584ece94189d70b'
    publishDir { "${params.outdir}/${meta.sampleid}/qc" }, mode: 'copy', pattern: '*_dedup_metrics.txt'

    input:
    tuple val(meta), path(sorted_bam)

    output:
    tuple val(meta), path("${meta.sampleid}_dedup.bam"), emit: bam
    path "${meta.sampleid}_dedup_metrics.txt", emit: metrics

    script:
    def jvm_mem = task.memory ? (task.memory.giga - 4) as int : 6
    """
    set -euo pipefail
    picard -Xmx${jvm_mem}g MarkDuplicates \
        MAX_RECORDS_IN_RAM=2000000 \
        VALIDATION_STRINGENCY=SILENT \
        I=${sorted_bam} \
        O=${meta.sampleid}_dedup.bam \
        M=${meta.sampleid}_dedup_metrics.txt
    """
}

process SAMTOOLS_CRAM {
    tag "${meta.sampleid}"
    container 'community.wave.seqera.io/library/bwa_samtools:cf87be72f0989a57'
    publishDir { "${params.outdir}/${meta.sampleid}" }, mode: 'copy', pattern: '*.cram*'
    publishDir { "${params.outdir}/${meta.sampleid}/qc" }, mode: 'copy', pattern: '*_flagstat.txt'

    input:
    tuple val(meta), path(dedup_bam)
    path reference_fa
    path ref_fai

    output:
    tuple val(meta), path("${meta.sampleid}.cram"), path("${meta.sampleid}.cram.crai"), emit: cram
    path "${meta.sampleid}_flagstat.txt", emit: flagstat

    script:
    """
    set -euo pipefail
    samtools view -@ ${task.cpus} -C -T ${reference_fa} -o ${meta.sampleid}.cram ${dedup_bam}
    samtools index ${meta.sampleid}.cram
    samtools flagstat ${meta.sampleid}.cram > ${meta.sampleid}_flagstat.txt
    """
}

process MULTIQC {
    tag "multiqc"
    container 'community.wave.seqera.io/library/multiqc:1.35--1ad1ebcf6f617695'
    publishDir "${params.outdir}/multiqc", mode: 'copy'

    input:
    path files

    output:
    path "multiqc_report.html"
    path "multiqc_data"

    script:
    """
    set -euo pipefail
    multiqc --no-ai .
    """
}

workflow {
    reads_ch = channel.fromPath(params.sample_sheet)
        .splitCsv(header: true, sep: ",")
        .map { row ->
            def meta = [
                sampleid: row.sample
            ]
            [meta, file(row.fastq_1, checkIfExists: true), file(row.fastq_2, checkIfExists: true)]
        }
        .groupTuple(by: 0)

    reference_fa_file  = file(params.reference_fa)
    def alt_path = new File(params.reference_fa + '.alt')
    reference_alt_file = alt_path.exists() ? file(params.reference_fa + '.alt') : []
    BWA_INDEX(reference_fa_file)
    SAMTOOLS_FAIDX(reference_fa_file)

    CONCAT_FASTQ(reads_ch)
    ADAPTER_TRIM(CONCAT_FASTQ.out)
    BWA_ALIGN(ADAPTER_TRIM.out.reads, reference_fa_file, BWA_INDEX.out, reference_alt_file)
    SAMTOOLS_SORT(BWA_ALIGN.out)
    MARK_DUPLICATES(SAMTOOLS_SORT.out)
    SAMTOOLS_CRAM(MARK_DUPLICATES.out.bam, reference_fa_file, SAMTOOLS_FAIDX.out)

    multiqc_input_ch = channel.empty()
        .mix(
            ADAPTER_TRIM.out.fastqc.collect(),
            ADAPTER_TRIM.out.log.collect(),
            MARK_DUPLICATES.out.metrics.collect(),
            SAMTOOLS_CRAM.out.flagstat.collect()
        )
        .collect()

    MULTIQC(multiqc_input_ch)
}

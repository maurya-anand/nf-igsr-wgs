SHELL         := bash
.SHELLFLAGS   := -euo pipefail -c

SAMPLE    ?=
FASTQ_DIR ?=
REF       ?=
REF_DIR   ?= reference
OUTDIR    ?= results
THREADS   ?= 16
SORT_MEM  ?= 4
JVM_MEM   ?= 28

REF_URL  := http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/GRCh38_reference_genome/GRCh38_full_analysis_set_plus_decoy_hla.fa
ALT_URL  := $(REF_URL).alt
FASTA    := $(REF_DIR)/GRCh38_full_analysis_set_plus_decoy_hla.fa

FASTQC_DIR := $(OUTDIR)/$(SAMPLE)/fastqc
TRIM_DIR   := $(OUTDIR)/$(SAMPLE)/trim_galore
QC_DIR     := $(OUTDIR)/$(SAMPLE)/qc
CRAM_DIR   := $(OUTDIR)/$(SAMPLE)

FQ1 := $(wildcard $(FASTQ_DIR)/*_1.fastq.gz)
FQ2 := $(wildcard $(FASTQ_DIR)/*_2.fastq.gz)

.PHONY: analyse download_reference index clean help check-params check-ref

index: check-ref $(REF).fai $(REF).bwt

help:
	$(info )
	$(info Usage: make -f scripts/Makefile <target> [OPTIONS])
	$(info )
	$(info Targets:)
	$(info   download_reference   download GRCh38 reference FASTA and ALT file to REF_DIR)
	$(info   index                build samtools faidx and BWA index for REF)
	$(info   analyse              run the full alignment workflow for one sample)
	$(info   clean                remove intermediate BAM and FASTQ files)
	$(info )
	$(info Parameters for download_reference:)
	$(info   REF_DIR     directory to download the reference into (default: reference))
	$(info )
	$(info Parameters for index:)
	$(info   REF         path to the reference FASTA to index [required])
	$(info )
	$(info Parameters for analyse:)
	$(info   SAMPLE      sample name used for all output files [required])
	$(info   FASTQ_DIR   directory containing paired *_1.fastq.gz and *_2.fastq.gz files [required])
	$(info   REF         path to GRCh38 reference FASTA [required])
	$(info   OUTDIR      output directory (default: results))
	$(info   THREADS     CPU threads (default: 16))
	$(info   SORT_MEM    memory per sort thread in GB (default: 4))
	$(info   JVM_MEM     Picard JVM heap size in GB (default: 28))
	$(info )
	$(info Examples:)
	$(info   make -f scripts/Makefile download_reference)
	$(info   make -f scripts/Makefile download_reference REF_DIR=/data/reference)
	$(info   make -f scripts/Makefile index)
	$(info   make -f scripts/Makefile analyse SAMPLE=HG00320 FASTQ_DIR=/data/HG00320 REF=../reference/GRCh38.fa)
	$(info )

check-ref:
	$(if $(REF),,$(error REF is required. Run 'make -f scripts/Makefile help' for usage))

check-params: check-ref
	$(if $(SAMPLE),,$(error SAMPLE is required. Run 'make -f scripts/Makefile help' for usage))
	$(if $(FASTQ_DIR),,$(error FASTQ_DIR is required. Run 'make -f scripts/Makefile help' for usage))

download_reference: $(FASTA) $(FASTA).alt

$(FASTA):
	mkdir -p $(REF_DIR)
	wget -c -O $@ $(REF_URL)

$(FASTA).alt:
	mkdir -p $(REF_DIR)
	wget -c -O $@ $(ALT_URL)

$(REF).fai: $(REF)
	samtools faidx $(REF)

$(REF).bwt: $(REF)
	bwa index $(REF)

analyse: check-params $(CRAM_DIR)/$(SAMPLE).cram

$(SAMPLE)_1.fastq.gz $(SAMPLE)_2.fastq.gz &: $(FQ1) $(FQ2)
	cat $(FQ1) > $(SAMPLE)_1.fastq.gz
	cat $(FQ2) > $(SAMPLE)_2.fastq.gz

$(SAMPLE)_1_trimmed.fq.gz $(SAMPLE)_2_trimmed.fq.gz &: $(SAMPLE)_1.fastq.gz $(SAMPLE)_2.fastq.gz | $(FASTQC_DIR) $(TRIM_DIR)
	export TMPDIR=$$PWD && \
	trim_galore \
	    --paired \
	    --illumina \
	    --fastqc \
	    --cores $(THREADS) \
	    $(SAMPLE)_1.fastq.gz $(SAMPLE)_2.fastq.gz
	mv $(SAMPLE)_1_val_1.fq.gz $(SAMPLE)_1_trimmed.fq.gz
	mv $(SAMPLE)_2_val_2.fq.gz $(SAMPLE)_2_trimmed.fq.gz
	mv *_fastqc.zip *_fastqc.html $(FASTQC_DIR)/
	mv *_trimming_report.txt $(TRIM_DIR)/

$(SAMPLE).bam: $(SAMPLE)_1_trimmed.fq.gz $(SAMPLE)_2_trimmed.fq.gz | $(REF).bwt
	bwa mem -Y -K 100000000 -t $(THREADS) \
	    -R "@RG\tID:$(SAMPLE)\tPL:ILLUMINA\tSM:$(SAMPLE)\tLB:$(SAMPLE)_lib" \
	    $(REF) $^ | \
	samtools view -@ $(THREADS) -b -o $@ -

$(SAMPLE)_sorted.bam: $(SAMPLE).bam
	samtools sort -@ $(THREADS) -m $(SORT_MEM)G -T $$PWD/$(SAMPLE)_tmp -o $@ $<

$(SAMPLE)_dedup.bam: $(SAMPLE)_sorted.bam | $(QC_DIR)
	picard -Xmx$(JVM_MEM)g MarkDuplicates \
	    MAX_RECORDS_IN_RAM=2000000 \
	    VALIDATION_STRINGENCY=SILENT \
	    I=$< \
	    O=$@ \
	    M=$(QC_DIR)/$(SAMPLE)_dedup_metrics.txt

$(CRAM_DIR)/$(SAMPLE).cram: $(SAMPLE)_dedup.bam | $(QC_DIR) $(CRAM_DIR)
	samtools view -@ $(THREADS) -C -T $(REF) -o $@ $<
	samtools index $@
	samtools flagstat $@ > $(QC_DIR)/$(SAMPLE)_flagstat.txt

$(FASTQC_DIR) $(TRIM_DIR) $(QC_DIR) $(CRAM_DIR):
	mkdir -p $@

clean:
	rm -f $(SAMPLE)_1.fastq.gz $(SAMPLE)_2.fastq.gz \
	      $(SAMPLE)_1_trimmed.fq.gz $(SAMPLE)_2_trimmed.fq.gz \
	      $(SAMPLE).bam $(SAMPLE)_sorted.bam $(SAMPLE)_dedup.bam

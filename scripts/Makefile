SHELL         := bash
.SHELLFLAGS   := -euo pipefail -c

SAMPLE    ?=
FASTQ_DIR ?=
REF       ?=
OUTDIR    ?= results
THREADS   ?= 16
SORT_MEM  ?= 4
JVM_MEM   ?= 28

FASTQC_DIR := $(OUTDIR)/$(SAMPLE)/fastqc
TRIM_DIR   := $(OUTDIR)/$(SAMPLE)/trim_galore
QC_DIR     := $(OUTDIR)/$(SAMPLE)/qc
CRAM_DIR   := $(OUTDIR)/$(SAMPLE)

FQ1 := $(wildcard $(FASTQ_DIR)/*_1.fastq.gz)
FQ2 := $(wildcard $(FASTQ_DIR)/*_2.fastq.gz)

.PHONY: all clean help check-params

help:
	$(info )
	$(info Usage: make -f scripts/Makefile SAMPLE=<name> FASTQ_DIR=<path> REF=<path> [OPTIONS])
	$(info )
	$(info Required:)
	$(info   SAMPLE      sample name used for all output files)
	$(info   FASTQ_DIR   directory containing paired *_1.fastq.gz and *_2.fastq.gz files)
	$(info   REF         path to GRCh38 reference FASTA)
	$(info )
	$(info Optional:)
	$(info   OUTDIR      output directory (default: results))
	$(info   THREADS     CPU threads (default: 16))
	$(info   SORT_MEM    memory per sort thread in GB (default: 4))
	$(info   JVM_MEM     Picard JVM heap size in GB (default: 28))
	$(info )
	$(info Example:)
	$(info   make -f scripts/Makefile SAMPLE=HG00320 FASTQ_DIR=/data/HG00320 REF=/ref/GRCh38.fa)
	$(info )

check-params:
	$(if $(SAMPLE),,$(error SAMPLE is required. Run 'make -f scripts/Makefile help' for usage))
	$(if $(FASTQ_DIR),,$(error FASTQ_DIR is required. Run 'make -f scripts/Makefile help' for usage))
	$(if $(REF),,$(error REF is required. Run 'make -f scripts/Makefile help' for usage))

all: check-params $(CRAM_DIR)/$(SAMPLE).cram

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

$(REF).bwt:
	bwa index $(REF)

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

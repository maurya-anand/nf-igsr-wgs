SHELL         := bash
.SHELLFLAGS   := -euo pipefail -c

SAMPLE    ?=
FASTQ_DIR ?=
REF       ?=
REF_DIR   ?= reference
OUTDIR    ?= results
THREADS   ?= $(shell nproc)
TOTAL_MEM := $(shell free -g 2>/dev/null | awk '/^Mem:/{print $$2}' || echo 32)
SORT_MEM  ?= $(shell awk "BEGIN{v=int(($(TOTAL_MEM)-8)/$(THREADS)); print (v<1)?1:v}")
JVM_MEM   ?= $(shell awk "BEGIN{v=$(TOTAL_MEM)-8; print (v<4)?4:v}")

REF_URL  := http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/GRCh38_reference_genome/GRCh38_full_analysis_set_plus_decoy_hla.fa
ALT_URL  := $(REF_URL).alt
FASTA    := $(REF_DIR)/GRCh38_full_analysis_set_plus_decoy_hla.fa

WORKDIR    := $(OUTDIR)/$(SAMPLE)/intermediate_files
FASTQC_DIR := $(OUTDIR)/$(SAMPLE)/fastqc
TRIM_DIR   := $(OUTDIR)/$(SAMPLE)/trim_galore
STATS_DIR  := $(OUTDIR)/$(SAMPLE)/alignment_stats
LOG_DIR    := $(OUTDIR)/$(SAMPLE)/logs
CRAM_DIR   := $(OUTDIR)/$(SAMPLE)/cram

FQ1 := $(wildcard $(FASTQ_DIR)/*_1.fastq.gz)
FQ2 := $(wildcard $(FASTQ_DIR)/*_2.fastq.gz)

.PHONY: analyse download_reference index clean clean_temp_files help check-params check-ref

help:
	$(info )
	$(info Usage: make -f scripts/Makefile <target> [OPTIONS])
	$(info )
	$(info Targets:)
	$(info   download_reference   download GRCh38 reference FASTA and ALT file to REF_DIR)
	$(info   index                build samtools faidx and BWA index for REF)
	$(info   analyse              run the full alignment workflow for one sample)
	$(info   clean_temp_files     remove intermediate_files/ for SAMPLE)
	$(info   clean                remove all output for SAMPLE)
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
	$(info   THREADS     CPU threads (default: all available via nproc))
	$(info   SORT_MEM    memory per sort thread in GB (default: auto-calculated from available RAM))
	$(info   JVM_MEM     Picard JVM heap size in GB (default: auto-calculated from available RAM))
	$(info )
	$(info Examples:)
	$(info   make -f scripts/Makefile download_reference)
	$(info   make -f scripts/Makefile download_reference REF_DIR=/data/reference)
	$(info   make -f scripts/Makefile index REF=/data/reference/GRCh38.fa)
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

index: check-ref $(REF).fai $(REF).bwt

$(REF).fai: $(REF)
	samtools faidx $(REF)

$(REF).bwt: $(REF)
	bwa index $(REF)

analyse: check-params $(OUTDIR)/$(SAMPLE)/multiqc/multiqc_report.html

$(WORKDIR)/$(SAMPLE)_1.fastq.gz $(WORKDIR)/$(SAMPLE)_2.fastq.gz &: $(FQ1) $(FQ2) | $(WORKDIR) $(LOG_DIR)
	cat $(FQ1) > $(WORKDIR)/$(SAMPLE)_1.fastq.gz
	cat $(FQ2) > $(WORKDIR)/$(SAMPLE)_2.fastq.gz

$(WORKDIR)/$(SAMPLE)_1_trimmed.fq.gz $(WORKDIR)/$(SAMPLE)_2_trimmed.fq.gz &: $(WORKDIR)/$(SAMPLE)_1.fastq.gz $(WORKDIR)/$(SAMPLE)_2.fastq.gz | $(FASTQC_DIR) $(TRIM_DIR) $(LOG_DIR)
	export TMPDIR=$(WORKDIR) && \
	trim_galore \
	    --paired \
	    --illumina \
	    --fastqc \
	    --cores $(THREADS) \
	    --output_dir $(WORKDIR) \
	    $^ \
	    >> $(LOG_DIR)/$(SAMPLE)_trim_galore.log 2>&1
	mv $(WORKDIR)/$(SAMPLE)_1_val_1.fq.gz $(WORKDIR)/$(SAMPLE)_1_trimmed.fq.gz
	mv $(WORKDIR)/$(SAMPLE)_2_val_2.fq.gz $(WORKDIR)/$(SAMPLE)_2_trimmed.fq.gz
	mv $(WORKDIR)/*_fastqc.zip $(WORKDIR)/*_fastqc.html $(FASTQC_DIR)/
	mv $(WORKDIR)/*_trimming_report.txt $(WORKDIR)/*_trimming_report.json $(TRIM_DIR)/

$(WORKDIR)/$(SAMPLE).bam: $(WORKDIR)/$(SAMPLE)_1_trimmed.fq.gz $(WORKDIR)/$(SAMPLE)_2_trimmed.fq.gz | $(REF).bwt $(LOG_DIR)
	bwa mem -Y -K 100000000 -t $(THREADS) \
	    -R "@RG\tID:$(SAMPLE)\tPL:ILLUMINA\tSM:$(SAMPLE)\tLB:$(SAMPLE)_lib" \
	    $(REF) $^ \
	    2>> $(LOG_DIR)/$(SAMPLE)_bwa.log | \
	samtools view -@ $(THREADS) -b -o $@ - \
	    2>> $(LOG_DIR)/$(SAMPLE)_bwa.log

$(WORKDIR)/$(SAMPLE)_sorted.bam: $(WORKDIR)/$(SAMPLE).bam
	samtools sort -@ $(THREADS) -m $(SORT_MEM)G -T $(WORKDIR)/$(SAMPLE)_tmp \
	    -o $@ $<

$(WORKDIR)/$(SAMPLE)_dedup.bam: $(WORKDIR)/$(SAMPLE)_sorted.bam | $(STATS_DIR) $(LOG_DIR)
	picard -Xmx$(JVM_MEM)g MarkDuplicates \
	    MAX_RECORDS_IN_RAM=2000000 \
	    VALIDATION_STRINGENCY=SILENT \
	    I=$< \
	    O=$@ \
	    M=$(STATS_DIR)/$(SAMPLE)_dedup_metrics.txt \
	    >> $(LOG_DIR)/$(SAMPLE)_markdup.log 2>&1

$(CRAM_DIR)/$(SAMPLE).cram: $(WORKDIR)/$(SAMPLE)_dedup.bam | $(STATS_DIR) $(CRAM_DIR)
	samtools view -@ $(THREADS) -C -T $(REF) -o $@ $<
	samtools index $@
	samtools flagstat $@ > $(STATS_DIR)/$(SAMPLE)_flagstat.txt

$(OUTDIR)/$(SAMPLE)/multiqc/multiqc_report.html: $(CRAM_DIR)/$(SAMPLE).cram | $(LOG_DIR)
	multiqc --no-ai --outdir $(OUTDIR)/$(SAMPLE)/multiqc $(OUTDIR)/$(SAMPLE) \
	    >> $(LOG_DIR)/$(SAMPLE)_multiqc.log 2>&1

$(WORKDIR) $(FASTQC_DIR) $(TRIM_DIR) $(STATS_DIR) $(CRAM_DIR) $(LOG_DIR):
	mkdir -p $@

clean_temp_files:
	rm -rf $(WORKDIR)

clean:
	rm -rf $(OUTDIR)/$(SAMPLE)

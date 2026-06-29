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

RUN_TS   := $(shell date '+%Y%m%d_%H%M%S')
RUN_LOG   = $(OUTDIR)/$(SAMPLE)_analyse_$(RUN_TS).log

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

CMD_CONCAT_R1 = cat $(FQ1) > $(WORKDIR)/$(SAMPLE)_1.fastq.gz
CMD_CONCAT_R2 = cat $(FQ2) > $(WORKDIR)/$(SAMPLE)_2.fastq.gz
CMD_TRIM      = export TMPDIR=$(WORKDIR) && trim_galore --paired --illumina --fastqc --cores $(THREADS) --output_dir $(WORKDIR) $(WORKDIR)/$(SAMPLE)_1.fastq.gz $(WORKDIR)/$(SAMPLE)_2.fastq.gz >> $(LOG_DIR)/$(SAMPLE)_trim_galore.log 2>&1
CMD_BWA       = bwa mem -Y -K 100000000 -t $(THREADS) -R '@RG\tID:$(SAMPLE)\tPL:ILLUMINA\tSM:$(SAMPLE)\tLB:$(SAMPLE)_lib' $(REF) $(WORKDIR)/$(SAMPLE)_1_trimmed.fq.gz $(WORKDIR)/$(SAMPLE)_2_trimmed.fq.gz 2>> $(LOG_DIR)/$(SAMPLE)_bwa.log | samtools view -@ $(THREADS) -b -o $(WORKDIR)/$(SAMPLE).bam - 2>> $(LOG_DIR)/$(SAMPLE)_bwa.log
CMD_SORT      = samtools sort -@ $(THREADS) -m $(SORT_MEM)G -T $(WORKDIR)/$(SAMPLE)_tmp -o $(WORKDIR)/$(SAMPLE)_sorted.bam $(WORKDIR)/$(SAMPLE).bam 2>> $(LOG_DIR)/$(SAMPLE)_sort.log
CMD_MARKDUP   = picard -Xmx$(JVM_MEM)g MarkDuplicates MAX_RECORDS_IN_RAM=2000000 VALIDATION_STRINGENCY=SILENT I=$(WORKDIR)/$(SAMPLE)_sorted.bam O=$(WORKDIR)/$(SAMPLE)_dedup.bam M=$(STATS_DIR)/$(SAMPLE)_dedup_metrics.txt >> $(LOG_DIR)/$(SAMPLE)_markdup.log 2>&1
CMD_CRAM      = samtools view -@ $(THREADS) -C -T $(REF) -o $(CRAM_DIR)/$(SAMPLE).cram $(WORKDIR)/$(SAMPLE)_dedup.bam
CMD_INDEX     = samtools index $(CRAM_DIR)/$(SAMPLE).cram
CMD_FLAGSTAT  = samtools flagstat $(CRAM_DIR)/$(SAMPLE).cram > $(STATS_DIR)/$(SAMPLE)_flagstat.txt
CMD_MULTIQC   = multiqc --no-ai --outdir $(OUTDIR)/$(SAMPLE)/multiqc $(OUTDIR)/$(SAMPLE) >> $(LOG_DIR)/$(SAMPLE)_multiqc.log 2>&1

LOG_INPUTS = printf '%s\t[analyse > $1]\t[INPUT]\t%s\n'  "$$(date '+%Y-%m-%d %H:%M:%S')" "$2" | tee -a $(RUN_LOG)
LOG_CMD    = printf '%s\t[analyse > $1]\t[CMD]\t%s\n'    "$$(date '+%Y-%m-%d %H:%M:%S')" "$2" | tee -a $(RUN_LOG)
LOG_OUTPUT = printf '%s\t[analyse > $1]\t[OUTPUT]\t%s\n' "$$(date '+%Y-%m-%d %H:%M:%S')" "$2" | tee -a $(RUN_LOG)

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
	@mkdir -p $(OUTDIR)
	@printf '%s\t[analyse]\t[INPUT]\t%s\n' "$$(date '+%Y-%m-%d %H:%M:%S')" "SAMPLE=$(SAMPLE) FASTQ_DIR=$(FASTQ_DIR) REF=$(REF) OUTDIR=$(OUTDIR) THREADS=$(THREADS) SORT_MEM=$(SORT_MEM) JVM_MEM=$(JVM_MEM)" | tee -a $(RUN_LOG)

download_reference: $(FASTA) $(FASTA).alt

$(FASTA):
	@mkdir -p $(REF_DIR)
	wget -c -O $@ $(REF_URL)

$(FASTA).alt:
	@mkdir -p $(REF_DIR)
	wget -c -O $@ $(ALT_URL)

index: check-ref $(REF).fai $(REF).bwt

$(REF).fai: $(REF)
	samtools faidx $(REF)

$(REF).bwt: $(REF)
	bwa index $(REF)

analyse: check-params $(OUTDIR)/$(SAMPLE)/multiqc/multiqc_report.html
	@printf '%s\t[analyse]\t[DONE]\t%s\n' "$$(date '+%Y-%m-%d %H:%M:%S')" "$(CRAM_DIR)/$(SAMPLE).cram" | tee -a $(RUN_LOG)

$(WORKDIR)/$(SAMPLE)_1.fastq.gz $(WORKDIR)/$(SAMPLE)_2.fastq.gz &: $(FQ1) $(FQ2) | $(WORKDIR) $(LOG_DIR)
	@$(call LOG_INPUTS,concat,SAMPLE=$(SAMPLE) FQ1=$(FQ1) FQ2=$(FQ2))
	@$(call LOG_CMD,concat,$(CMD_CONCAT_R1))
	@$(CMD_CONCAT_R1)
	@$(call LOG_CMD,concat,$(CMD_CONCAT_R2))
	@$(CMD_CONCAT_R2)
	@$(call LOG_OUTPUT,concat,$(WORKDIR)/)

$(WORKDIR)/$(SAMPLE)_1_trimmed.fq.gz $(WORKDIR)/$(SAMPLE)_2_trimmed.fq.gz &: $(WORKDIR)/$(SAMPLE)_1.fastq.gz $(WORKDIR)/$(SAMPLE)_2.fastq.gz | $(FASTQC_DIR) $(TRIM_DIR) $(LOG_DIR)
	@$(call LOG_INPUTS,trim_galore,SAMPLE=$(SAMPLE) THREADS=$(THREADS) IN1=$(WORKDIR)/$(SAMPLE)_1.fastq.gz IN2=$(WORKDIR)/$(SAMPLE)_2.fastq.gz)
	@$(call LOG_CMD,trim_galore,$(CMD_TRIM))
	@$(CMD_TRIM)
	@mv $(WORKDIR)/$(SAMPLE)_1_val_1.fq.gz $(WORKDIR)/$(SAMPLE)_1_trimmed.fq.gz
	@mv $(WORKDIR)/$(SAMPLE)_2_val_2.fq.gz $(WORKDIR)/$(SAMPLE)_2_trimmed.fq.gz
	@mv $(WORKDIR)/*_fastqc.zip $(WORKDIR)/*_fastqc.html $(FASTQC_DIR)/
	@mv $(WORKDIR)/*_trimming_report.txt $(WORKDIR)/*_trimming_report.json $(TRIM_DIR)/
	@$(call LOG_OUTPUT,trim_galore,$(WORKDIR)/)

$(WORKDIR)/$(SAMPLE).bam: $(WORKDIR)/$(SAMPLE)_1_trimmed.fq.gz $(WORKDIR)/$(SAMPLE)_2_trimmed.fq.gz | $(REF).bwt $(LOG_DIR)
	@$(call LOG_INPUTS,bwa_mem,SAMPLE=$(SAMPLE) THREADS=$(THREADS) REF=$(REF) IN1=$(WORKDIR)/$(SAMPLE)_1_trimmed.fq.gz IN2=$(WORKDIR)/$(SAMPLE)_2_trimmed.fq.gz)
	@$(call LOG_CMD,bwa_mem,$(CMD_BWA))
	@$(CMD_BWA)
	@$(call LOG_OUTPUT,bwa_mem,$(WORKDIR)/)

$(WORKDIR)/$(SAMPLE)_sorted.bam: $(WORKDIR)/$(SAMPLE).bam
	@$(call LOG_INPUTS,samtools_sort,SAMPLE=$(SAMPLE) THREADS=$(THREADS) SORT_MEM=$(SORT_MEM)G IN=$(WORKDIR)/$(SAMPLE).bam)
	@$(call LOG_CMD,samtools_sort,$(CMD_SORT))
	@$(CMD_SORT)
	@$(call LOG_OUTPUT,samtools_sort,$(WORKDIR)/)

$(WORKDIR)/$(SAMPLE)_dedup.bam: $(WORKDIR)/$(SAMPLE)_sorted.bam | $(STATS_DIR) $(LOG_DIR)
	@$(call LOG_INPUTS,picard_markdup,SAMPLE=$(SAMPLE) JVM_MEM=$(JVM_MEM)g IN=$(WORKDIR)/$(SAMPLE)_sorted.bam)
	@$(call LOG_CMD,picard_markdup,$(CMD_MARKDUP))
	@$(CMD_MARKDUP)
	@$(call LOG_OUTPUT,picard_markdup,$(WORKDIR)/)

$(CRAM_DIR)/$(SAMPLE).cram: $(WORKDIR)/$(SAMPLE)_dedup.bam | $(STATS_DIR) $(CRAM_DIR)
	@$(call LOG_INPUTS,samtools_cram,SAMPLE=$(SAMPLE) THREADS=$(THREADS) REF=$(REF) IN=$(WORKDIR)/$(SAMPLE)_dedup.bam)
	@$(call LOG_CMD,samtools_cram,$(CMD_CRAM))
	@$(CMD_CRAM)
	@$(call LOG_CMD,samtools_cram,$(CMD_INDEX))
	@$(CMD_INDEX)
	@$(call LOG_CMD,samtools_cram,$(CMD_FLAGSTAT))
	@$(CMD_FLAGSTAT)
	@$(call LOG_OUTPUT,samtools_cram,$(CRAM_DIR)/)

$(OUTDIR)/$(SAMPLE)/multiqc/multiqc_report.html: $(CRAM_DIR)/$(SAMPLE).cram | $(LOG_DIR)
	@$(call LOG_INPUTS,multiqc,SAMPLE=$(SAMPLE) IN=$(OUTDIR)/$(SAMPLE)/)
	@$(call LOG_CMD,multiqc,$(CMD_MULTIQC))
	@$(CMD_MULTIQC)
	@$(call LOG_OUTPUT,multiqc,$(OUTDIR)/$(SAMPLE)/multiqc/)

$(WORKDIR) $(FASTQC_DIR) $(TRIM_DIR) $(STATS_DIR) $(CRAM_DIR) $(LOG_DIR):
	@mkdir -p $@

clean_temp_files:
	@rm -rf $(WORKDIR)

clean:
	@rm -rf $(OUTDIR)/$(SAMPLE)

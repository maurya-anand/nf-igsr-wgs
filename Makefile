REF_DIR = ../reference
FASTA = $(REF_DIR)/GRCh38_full_analysis_set_plus_decoy_hla.fa
ALT = $(FASTA).alt

.PHONY: reference clean index index-singularity

reference: $(FASTA) $(ALT)

$(REF_DIR):
	mkdir -p $(REF_DIR)

$(FASTA): | $(REF_DIR)
	wget -c -O $@ http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/GRCh38_reference_genome/GRCh38_full_analysis_set_plus_decoy_hla.fa

$(ALT): | $(REF_DIR)
	wget -c -O $@ http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/GRCh38_reference_genome/GRCh38_full_analysis_set_plus_decoy_hla.fa.alt

index:
	samtools faidx $(FASTA)
	bwa index $(FASTA)

index-singularity:
	singularity exec docker://quay.io/biocontainers/samtools:1.17--h00782f0_1 samtools faidx $(FASTA)
	singularity exec docker://quay.io/biocontainers/bwa:0.7.17--he4a0461_11 bwa index $(FASTA)

clean:
	rm -rf $(REF_DIR)

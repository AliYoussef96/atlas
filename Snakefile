"""
combining samples into a single fastq can take place after intial qc -- all files are interleaved
concatenate into single file; push through the remainder of the workflow
these qc'd files are then used for counts per sample across the assembled contigs
"""
import json
import os
import sys
import tempfile
from subprocess import check_output


def get_count_tables(config, key):
    expected_tables = []
    for name, vals in config[key].items():
        if name.lower() == "taxonomy":
            tax_levels = vals.get("levels", ["species"])
            for level in tax_levels:
                level = level.lower()
                tax_name = "taxonomy_%s" % level
                for subname, subvals in vals.items():
                    if subname.lower() == "levels": continue
                    expected_tables.append("%s_%s" % (subname, tax_name))
        else:
            expected_tables.append(name)
    return expected_tables


def get_assembler(config):
    if config["assembly"]["assembler"] == "spades":
        return "spades_{k}".format(k=config["assembly"].get("spades_k", "auto").replace(",", "_"))
    else:
        k_min = config["assembly"].get("kmer_min", 21)
        k_max = config["assembly"].get("kmer_max", 121)
        k_step = config["assembly"].get("kmer_step", 20)
        return "megahit_{min}_{max}_{step}".format(min=k_min, max=k_max, step=k_step)


def get_temp_dir(config):
    if config.get("tmpdir"):
        return config["tmpdir"]
    else:
        return tempfile.gettempdir()


def init_complete_config(config):
    config_report = []
    if not config.get("samples"):
        config_report.append("'samples' is not defined")
    if not len(config["samples"].keys()) > 0:
        config_report.append("no samples are defined under 'samples:'")
    # TODO


# shell prefixes for multi-threaded and single-threads tasks
SHPFXM = config.get("prefix") + str(config.get("threads")) if config.get("prefix") else ""
SHPFXS = config.get("prefix") + "1" if config.get("prefix") else ""
SAMPLES = list(config["samples"].keys())
TABLES = get_count_tables(config, "summary_counts")
NORMALIZATION = "normalization_k%d_t%d" % (config["preprocessing"]["normalization"].get("k", 31), config["preprocessing"]["normalization"].get("t", 100))
ASSEMBLER = get_assembler(config)
TMPDIR = get_temp_dir(config)


if config.get("workflow", "complete") == "complete":
    init_complete_config(config)
    rule all:
        input:
            expand("{sample}/quality_control/decontamination/{sample}_{decon_dbs}.fastq.gz", sample=SAMPLES, decon_dbs=list(config["preprocessing"]["contamination"]["references"].keys())),
            expand("{sample}/quality_control/decontamination/{sample}_refstats.txt", sample=SAMPLES),
            expand("{sample}/quality_control/%s/{sample}_pe.fastq.gz" % NORMALIZATION, sample=SAMPLES),
            expand("{sample}/quality_control/fastqc/{sample}_pe_fastqc.zip", sample=SAMPLES),
            expand("{sample}/quality_control/fastqc/{sample}_pe_fastqc.html", sample=SAMPLES),
            expand("{sample}/%s/{sample}_contigs.fasta" % ASSEMBLER, sample=SAMPLES),
            expand("{sample}/annotation/orfs/{sample}.faa", sample=SAMPLES),
            expand("{sample}/%s/stats/prefilter_contig_stats.txt" % ASSEMBLER, sample=SAMPLES),
            expand("{sample}/%s/stats/final_contig_stats.txt" % ASSEMBLER, sample=SAMPLES),
            expand("{sample}/annotation/{reference}/{sample}_hits.tsv", reference=list(config["annotation"]["references"].keys()), sample=SAMPLES),
            expand("{sample}/annotation/{reference}/{sample}_assignments.tsv", reference=list(config["annotation"]["references"].keys()), sample=SAMPLES),
            expand("{sample}/annotation/{sample}_merged_assignments.tsv", sample=SAMPLES),
            expand("{sample}/count_tables/{sample}_{table}.tsv", sample=SAMPLES, table=TABLES),
            expand("{sample}/{sample}_readme.html", sample=SAMPLES)

    include: "rules/quality_control/fastq_filter.snakefile"
    include: "rules/quality_control/error_correction.snakefile"
    include: "rules/quality_control/contig_filters.snakefile"
    include: "rules/quality_control/decontamination.snakefile"
    include: "rules/quality_control/normalization.snakefile"
    include: "rules/quality_control/fastqc.snakefile"
    if config["assembly"]["assembler"] == "spades":
        include: "rules/assemblers/spades.snakefile"
    else:
        include: "rules/assemblers/megahit.snakefile"
    include: "rules/annotation/diamond.snakefile"
    include: "rules/annotation/prodigal.snakefile"
    include: "rules/annotation/verse.snakefile"
    include: "rules/annotation/munging.snakefile"
    include: "rules/reports/sample.snakefile"
else:
    print("Workflow %s is not a defined workflow." % config.get("workflow", "[no --workflow specified]"), file=sys.stderr)

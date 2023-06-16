##STARsolo
##remember that reads are swapped in internals.snakefile!!
###currently having CB and UB tags output in the bam requires --outSAMtype SortedByCoordinate !!
import numpy
import os

rule STARsolo:
    input:
        r1="originalFASTQ/{sample}"+reads[0]+".fastq.gz",
        r2="originalFASTQ/{sample}"+reads[1]+".fastq.gz",
        annot="Annotation/genes.filtered.gtf"
    output:
        bam = "STARsolo/{sample}.sorted.bam",
        raw_counts = "STARsolo/{sample}/{sample}.Solo.out/Gene/raw/matrix.mtx",
        filtered_counts = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/matrix.mtx",
        filtered_bc = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/barcodes.tsv",
        raw_features = "STARsolo/{sample}/{sample}.Solo.out/Gene/raw/features.tsv",
        filtered_features = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/features.tsv"
    log: "STARsolo/logs/{sample}.log"
    params:
        alignerOptions = str(alignerOptions or ''),
        gtf = outdir+"/Annotation/genes.filtered.gtf",
        idx = os.path.dirname(star_index_allelic),
        prefix = "STARsolo/{sample}/{sample}.",
        samsort_memory = '2G',
        sample_dir = "STARsolo/{sample}",
        bclist = BCwhiteList,
        UMIstart = STARsoloCoords[0],
        UMIlen = STARsoloCoords[1],
        CBstart = STARsoloCoords[2],
        CBlen = STARsoloCoords[3],
        outdir = outdir,
        tempDir = tempDir
    benchmark:
        aligner+"/.benchmark/STARsolo.{sample}.benchmark"
    threads: 20  # 3.2G per core
    conda: CONDA_scRNASEQ_ENV
    shell: """
        TMPDIR={params.tempDir}
        MYTEMP=$(mktemp -d ${{TMPDIR:-/tmp}}/snakepipes.XXXXXXXXXX);
        ( [ -d {params.sample_dir} ] || mkdir -p {params.sample_dir} )
        ~/tools/STARdev/bin/Linux_x86_64/STAR --runThreadN {threads} \
            {params.alignerOptions} \
              --alignEndsType EndToEnd \
              --outFilterMultimapNmax 20 \
              --alignSJoverhangMin 8 \
              --alignSJDBoverhangMin 1 \
              --outFilterMismatchNmax 999 \
              --alignIntronMin 1 \
              --alignIntronMax 1000000 \
              --alignMatesGapMax 1000000 \
            --sjdbOverhang 100 \
            --outSAMunmapped Within \
            --outSAMtype BAM SortedByCoordinate \
            --outBAMsortingBinsN 20 \
            --outSAMattributes NH HI AS nM CB UB NM MD \
            --sjdbGTFfile {params.gtf} \
            --genomeDir {params.idx} \
            --readFilesIn  {input.r1} {input.r2} \
            --readFilesCommand gunzip -c \
            --outFileNamePrefix {params.prefix} \
	        --soloType CB_UMI_Simple \
            --soloFeatures Gene Velocyto \
            --soloUMIstart {params.UMIstart} \
            --soloUMIlen {params.UMIlen} \
            --soloCBstart {params.CBstart} \
            --soloCBlen {params.CBlen} \
            --soloCBwhitelist {params.bclist} \
            --soloBarcodeReadLength 0 \
            --soloCBmatchWLtype 1MM_multi_pseudocounts \
            --soloUMIfiltering MultiGeneUMI \
            --soloStrand Forward \
            --soloCellFilter EmptyDrops_CR \
            --soloUMIdedup Exact 2> {log}

        ln -s {params.outdir}/{params.prefix}Aligned.sortedByCoord.out.bam {params.outdir}/{output.bam} 2>> {log}
 
        rm -rf $MYTEMP
         """


rule filter_bam:
    input:
        bamfile = aligner+"/{sample}.sorted.bam",
        bami = aligner+"/{sample}.sorted.bam.bai"
    output:
        bamfile = "filtered_bam/{sample}.filtered.bam",
        bami = "filtered_bam/{sample}.filtered.bam.bai"
    log: "filtered_bam/logs/{sample}.log"
    threads: 8
    conda: CONDA_SAMBAMBA_ENV
    shell: """
           sambamba view -F "not unmapped and [CB] !=null" -t {threads} -f bam {input.bamfile} > {output.bamfile} 2> {log};
           sambamba index -t {threads} {output.bamfile} 2>> {log}
           """


rule gzip_STARsolo_for_seurat:
    input:
        raw_counts = "STARsolo/{sample}/{sample}.Solo.out/Gene/raw/matrix.mtx",
        filtered_counts = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/matrix.mtx"
    output:
        raw_counts_gz = "STARsolo/{sample}/{sample}.Solo.out/Gene/raw/matrix.mtx.gz",
        filtered_counts_gz = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/matrix.mtx.gz"
    params:
        raw_bc = "STARsolo/{sample}/{sample}.Solo.out/Gene/raw/barcodes.tsv",
        filtered_bc = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/barcodes.tsv",
        raw_features = "STARsolo/{sample}/{sample}.Solo.out/Gene/raw/features.tsv",
        filtered_features = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/features.tsv",
        raw_bc_gz = "STARsolo/{sample}/{sample}.Solo.out/Gene/raw/barcodes.tsv.gz",
        filtered_bc_gz = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/barcodes.tsv.gz",
        raw_features_gz = "STARsolo/{sample}/{sample}.Solo.out/Gene/raw/features.tsv.gz",
        filtered_features_gz = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/features.tsv.gz"
    log: "STARsolo/logs/{sample}.gzip.log"
    shell: """
         gzip -c {params.raw_bc} > {params.raw_bc_gz} 2> {log};
         gzip -c {params.raw_features} > {params.raw_features_gz} 2>> {log};
         gzip -c {params.filtered_bc} > {params.filtered_bc_gz} 2>> {log};
         gzip -c {params.filtered_features} > {params.filtered_features_gz} 2>> {log};
         gzip -c {input.raw_counts} > {output.raw_counts_gz} 2>> {log};
         gzip -c {input.filtered_counts} > {output.filtered_counts_gz} 2>> {log}
    """


rule STARsolo_raw_to_seurat:
    input:
        infiles = expand("STARsolo/{sample}/{sample}.Solo.out/Gene/raw/matrix.mtx.gz",sample=samples)
    output:
        seurat = "Seurat/STARsolo_raw/merged_samples.RDS"
    params:
        indirs = expand(outdir + "/STARsolo/{sample}/{sample}.Solo.out/Gene/raw",sample=samples),
        wdir = outdir + "/Seurat/STARsolo_raw",
        samples = samples
    log:
        out = "Seurat/STARsolo_raw/logs/seurat.out"
    conda: CONDA_seurat3_ENV
    script: "../rscripts/scRNAseq_Seurat3.R"

rule STARsolo_filtered_to_seurat:
    input:
        infiles = expand("STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/matrix.mtx.gz",sample=samples)
    output:
        seurat = "Seurat/STARsolo_filtered/merged_samples.RDS"
    params:
        indirs = expand(outdir +"/STARsolo/{sample}/{sample}.Solo.out/Gene/filtered",sample=samples),
        wdir = outdir +"/Seurat/STARsolo_filtered",
        samples = samples
    log:
        out = "Seurat/STARsolo_filtered/logs/seurat.out"
    conda: CONDA_seurat3_ENV
    script: "../rscripts/scRNAseq_Seurat3.R"

if not skipVelocyto:
    rule cellsort_bam:
        input:
            bam = "filtered_bam/{sample}.filtered.bam"
        output:
            bam = "filtered_bam/cellsorted_{sample}.filtered.bam"
        log: "filtered_bam/logs/{sample}.cellsort.log"
        params:
            samsort_memory="10G",
            tempDir = tempDir
        threads: 4
        conda: CONDA_scRNASEQ_ENV
        shell: """
                TMPDIR={params.tempDir}
                MYTEMP=$(mktemp -d ${{TMPDIR:-/tmp}}/snakepipes.XXXXXXXXXX)
                samtools sort -m {params.samsort_memory} -@ {threads} -T $MYTEMP/{wildcards.sample} -t CB -O bam -o {output.bam} {input.bam} 2> {log}
                rm -rf $MYTEMP
               """

    #the barcode whitelist is currently taken from STARsolo filtered output, this is required to reduce runtime!
    #velocyto doesn't accept our filtered gtf; will have to use the mask, after all
    #no metadata table is provided

    checkpoint velocyto:
        input:
            gtf = "Annotation/genes.filtered.gtf",
            bam = "filtered_bam/{sample}.filtered.bam",
            csbam="filtered_bam/cellsorted_{sample}.filtered.bam",
            bc = "STARsolo/{sample}/{sample}.Solo.out/Gene/filtered/barcodes.tsv"
        output:
            outdir = directory("VelocytoCounts/{sample}"),
            outdum = "VelocytoCounts/{sample}.done.txt"
        log: "VelocytoCounts/logs/{sample}.log"
        params:
            tempdir = tempDir
        conda: CONDA_scRNASEQ_ENV
        shell: """
                export LC_ALL=en_US.utf-8
                export LANG=en_US.utf-8
                export TMPDIR={params.tempdir}
                MYTEMP=$(mktemp -d ${{TMPDIR:-/tmp}}/snakepipes.XXXXXXXXXX);
                velocyto run --bcfile {input.bc} --outputfolder {output.outdir} --dtype uint64 {input.bam} {input.gtf} 2> {log};
                touch {output.outdum};
                rm -rf $MYTEMP
        """

    rule combine_loom:
        input: expand("VelocytoCounts/{sample}",sample=samples)
        output: "VelocytoCounts_merged/merged.loom"
        log: "VelocytoCounts_merged/logs/combine_loom.log"
        conda: CONDA_loompy_ENV
        params:
            outfile = outdir+"/VelocytoCounts_merged/merged.loom",
            script = maindir+"/shared/tools/loompy_merge.py",
            input_fp = lambda wildcards,input: [ os.path.join(outdir,f) for f in input ]
        shell: """
            python {params.script} -outf {params.outfile} {params.input_fp} 2> {log}
              """

    #rule velocity_to_seurat:
    #    input:
    #        indirs = expand("VelocytoCounts/{sample}",sample=samples)
    #    output:
    #        seurat = "Seurat/Velocyto/merged_samples.RDS"
    #    params:
    #        wdir = outdir + "/Seurat/Velocyto",
    #        samples = samples
    #    log:
    #        out = "Seurat/Velocyto/logs/seurat.out"
    #    conda: CONDA_seurat3_ENV
    #    script: "../rscripts/scRNAseq_merge_loom.R"
    


##seperate two alleles using SNPsplit
rule snp_split:
    input:
        snp = SNPFile,
        bam = "filtered_bam/{sample}.filtered.bam"
    output:
        expand("allelic_bams/{{sample}}.{suffix}.bam", suffix = ['allele_flagged', 'genome1', 'genome2', 'unassigned'])
    log: "allelic_bams/logs/{sample}.snp_split.log"
    params:
        pairedEnd = '--paired' if pairedEnd else '',
        outdir = "allelic_bams",
        bam = expand("allelic_bams/{{sample}}.filtered.{suffix}.bam", suffix = ['allele_flagged', 'genome1', 'genome2', 'unassigned'])
    conda: CONDA_SHARED_ENV
    shell:
        "SNPsplit {params.pairedEnd}"
        " -o {params.outdir} --snp_file {input.snp} {input.bam} 2> {log}"
        " && rename '.filtered' '' {params.bam}"


##############################
##Count each allele seperately
##############################

## For both allele

## featurecounts (insert gene_id belonging tag to the bam file)

rule featureCounts_allele_both:
    input:
        gtf = "Annotation/genes.filtered.gtf",
        bam = "allelic_bams/{sample}.{allele}.bam",
    output:
        out_bam = temp('featureCounts/{sample}.{allele}.bam.featureCounts.bam'),
        out_bam_sort = 'featureCounts/{sample}.{allele}.bam.featureCounts.sorted.bam'
    params:
        name = 'featureCounts/{sample}.{allele}.featurecounts',
        libtype = libraryType,
        paired_opt = lambda wildcards: "-p -B " if pairedEnd else "",
        tempDir = tempDir
    log:
        out = "featureCounts/logs/{sample}.{allele}.featurecount.out",
        err = "featureCounts/logs/{sample}.{allele}.featurecount.err"
    threads: 10
    conda: CONDA_RNASEQ_ENV
    shell: """
        TMPDIR={params.tempDir}
        MYTEMP=$(mktemp -d ${{TMPDIR:-/tmp}}/snakepipes.XXXXXXXXXX);
        featureCounts \
        {params.paired_opt} \
        -T {threads} \
        -s {params.libtype} \
        -a {input.gtf} \
        -o {params.name} -R BAM \
        --tmpDir $MYTEMP \
        {input.bam} > {log.out} 2> {log.err} \
        && samtools sort -@ {threads} {output.out_bam} -o {output.out_bam_sort} \
        && samtools index -@ {threads} {output.out_bam_sort};
        rm -rf $MYTEMP
        """

## Umitools count the UMI per barcode 

rule umitools_allele_both:
    input:
        'featureCounts/{sample}.{allele}.bam.featureCounts.sorted.bam',
    output:
        'featureCounts/{sample}.{allele}.counts.tsv.gz'
    params:
    log:
        out = "featureCounts/logs/{sample}.{allele}.umitools.out",
        err = "featureCounts/logs/{sample}.{allele}.umitools.err"
    threads: 3
    conda: CONDA_scRNASEQ_ENV
    log:
        out = "featureCounts/logs/{sample}.{allele}.umi_count.out",
        err = "featureCounts/logs/{sample}.{allele}.umi_count.err"
    shell: """
        umi_tools count \
        --extract-umi-method=tag \
        --umi-tag=UB --cell-tag=CB \
        --per-gene --gene-tag=XT --assigned-status-tag=XS \
        --per-cell --method cluster \
        -I {input} -S {output} -L {log.out} -E {log.err}
        """

rule ReportCounts:
    input:
        expand("featureCounts/{{sample}}.{allele}.counts.tsv.gz", allele=["allele_flagged","genome1","genome2"])
    output:
        "featureCounts/{sample}.umicounts.report.txt"
    run:
        file = open(output[0],"w")
        file.write("everything is done")
        file.close()


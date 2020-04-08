### Bowtie2 ####################################################################
if pairedEnd:
    rule Bowtie2:
        input:
            r1 = fastq_dir+"/{sample}"+reads[0]+".fastq.gz",
            r2 = fastq_dir+"/{sample}"+reads[1]+".fastq.gz"
        output:
            align_summary = "Bowtie2/{sample}.Bowtie2_summary.txt",
            bam = temp("Bowtie2/{sample}.sorted.bam")# removing since we keep the sambamba output (dupmarked)
        log: "Bowtie2/logs/{sample}.sort.log"
        params:
            bowtie2_index=bowtie2_index,
            alignerOpts = str(alignerOpts or ''),
            mateOrientation = mateOrientation,
            insertSizeMax = insertSizeMax,
            tempDir = tempDir
        benchmark:
            "Bowtie2/.benchmark/Bowtie2.{sample}.benchmark"
        threads: 24  # 1G per core
        conda: CONDA_DNA_MAPPING_ENV
        shell: """
            TMPDIR={params.tempDir}
            MYTEMP=$(mktemp -d ${{TMPDIR:-/tmp}}/snakepipes.XXXXXXXXXX);
            bowtie2 \
            -X {params.insertSizeMax} \
            -x {params.bowtie2_index} -1 {input.r1} -2 {input.r2} \
            {params.alignerOpts} {params.mateOrientation} \
            --rg-id {wildcards.sample} \
            --rg DS:{wildcards.sample} --rg PL:ILLUMINA --rg SM:{wildcards.sample} \
            -p {threads} \
            2> {output.align_summary} | \
            samtools view -Sb - | \
            samtools sort -m 2G -T $MYTEMP/{wildcards.sample} -@ 2 -O bam - > {output.bam} 2> {log};
            rm -rf $MYTEMP
            """
else:
    rule Bowtie2:
        input:
            fastq_dir+"/{sample}"+reads[0]+".fastq.gz"
        output:
            align_summary = "Bowtie2/{sample}.Bowtie2_summary.txt",
            bam = temp("Bowtie2/{sample}.sorted.bam")
        log: "Bowtie2/logs/{sample}.sort.log"
        params:
            bowtie2_index=bowtie2_index,
            alignerOpts = str(alignerOpts or ''),
            tempDir = tempDir
        benchmark:
            "Bowtie2/.benchmark/Bowtie2.{sample}.benchmark"
        threads: 24  # 1G per core
        conda: CONDA_DNA_MAPPING_ENV
        shell: """
            TMPDIR={params.tempDir}
            MYTEMP=$(mktemp -d ${{TMPDIR:-/tmp}}/snakepipes.XXXXXXXXXX);
            bowtie2 \
            -x {params.bowtie2_index} -U {input} \
            {params.alignerOpts} \
            --rg-id {wildcards.sample} \
            --rg DS:{wildcards.sample} --rg PL:ILLUMINA --rg SM:{wildcards.sample} \
            -p {threads} \
            2> {output.align_summary} | \
            samtools view -Sbu - | \
            samtools sort -m 2G -T $MYTEMP/{wildcards.sample} -@ 2 -O bam - > {output.bam} 2> {log};
            rm -rf $MYTEMP
            """

//This is a nextflow script to be run with
//nextflow run cutlo.nf
//Performs basic cutadapt trimming, then alignment with bwa, then variant calling with lofreq

params.filepattern = "/usr/share/sequencing/miseq/output/161007_M01745_0131_000000000-ATN6R/Data/Intensities/BaseCalls/049*{_L001_R1_001,_L001_R2_001}.fastq.gz"
params.adapterfile = "/usr/share/sequencing/references/adapters/NexteraPE-PE.fa" //alternatively use TruSeq for Nextseq runs
params.outdir = "/home/AD/tbleazar/test"
params.referencefolder = "/usr/share/sequencing/projects/049/input/reference/" //and it is required that this have an indexed genome already
params.referencefile = "AY184219.fasta"
params.cpus = "32"

Channel
  .fromFilePairs(params.filepattern)
  .set { readpairs }

references = Channel
  .fromPath(params.referencefolder)

references.into {
  ref1
  ref2
  ref3
  ref4
}

process docutadapt {
  publishDir "$params.outdir/alignments", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '4 GB'

  input:
  set ( sampleprefix, file(samples) ) from readpairs

  output:
  set ( sampleprefix, file("${sampleprefix}_L001_R1_001.trimmed.fastq.gz"), file("${sampleprefix}_L001_R2_001.trimmed.fastq.gz") ) into (trimmingoutput1, trimmingoutput2)
  file("${sampleprefix}.trim.out") into trimouts

  script:
  """
  module load CUTAdapt/latest
  cutadapt -a file:${params.adapterfile} -A file:${params.adapterfile} -g file:${params.adapterfile} -G file:${params.adapterfile} -o ${sampleprefix}_L001_R1_001.trimmed.fastq.gz -p ${sampleprefix}_L001_R2_001.trimmed.fastq.gz ${samples[0]} ${samples[1]} -q 30,30 --minimum-length 50 --times 40 -e 0.1 --max-n 0 > ${sampleprefix}.trim.out 2> ${sampleprefix}.trim.err
  """
}

process dotrimlog {
  publishDir "$params.outdir/analysis", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '4 GB'

  input:
  file "logdir/*" from trimouts.toSortedList()

  output:
  file("trimming-summary.csv") into trimlogend

  script:
  """
  module load anaconda/Py2/python2
  python $HOME/CODE/core/utilities/logger.py logdir trimming-summary.csv cutadapt
  """
}

process doalignment {
  publishDir "$params.outdir/alignments", mode: "copy"
  cpus 32
  queue 'WORK'
  time '12h'
  memory '10 GB'

  input:
  set (sampleprefix, file(forwardtrimmed), file(reversetrimmed)) from trimmingoutput1
  file refs from ref1.first()

  output:
  set (sampleprefix, file("${sampleprefix}.unsorted.sam") ) into samfile

  script:
  """
  module load BWA/latest
  bwa mem -t ${params.cpus} -R '@RG\\tID:${sampleprefix}\\tSM:${sampleprefix}\\tPL:Illumina' ${refs}/${params.referencefile} ${forwardtrimmed} ${reversetrimmed} > ${sampleprefix}.unsorted.sam
  """
}

process sorttobam {
  publishDir "$params.outdir/alignments", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '24 GB'

  input:
  set ( sampleprefix, file(unsortedsam) ) from samfile

  output:
  set ( sampleprefix, file("${sampleprefix}.sorted.bam") ) into sortedbam

  """
  module load SAMTools/latest
  samtools sort -o ${sampleprefix}.sorted.bam -O BAM -@ ${params.cpus} ${unsortedsam}
  """
}

process markduplicates {
  publishDir "$params.outdir/alignments", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '24 GB'

  input:
  set ( sampleprefix, file(sortedbamfile) ) from sortedbam

  output:
  set ( sampleprefix, file("${sampleprefix}.marked.bam") ) into markedbam

  """
  module load GATK/4.1.3.0
  gatk MarkDuplicates -I $sortedbamfile -M ${sampleprefix}.metrics.txt -O ${sampleprefix}.marked.bam
  """
}

process indelqual {
  publishDir "$params.outdir/alignments", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '24 GB'

  input:
  set ( sampleprefix, file(markedbamfile) ) from markedbam
  file refs from ref3.first()

  output:
  set ( sampleprefix, file("${sampleprefix}.indelqual.bam") ) into (indelqualforindex, indelqualforcall)

  """
  module load LoFREQ/latest
  lofreq indelqual --dindel -f ${refs}/${params.referencefile} -o ${sampleprefix}.indelqual.bam $markedbamfile
  """
}

process samtoolsindex {
  publishDir "$params.outdir/alignments", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '24 GB'

  input:
  set ( sampleprefix, file(indelqualfile) ) from indelqualforindex

  output:
  set ( sampleprefix, file("${indelqualfile}.bai") ) into samindex
  file("${sampleprefix}.flagstat.out") into flagstatouts

  """
  module load SAMTools/latest
  samtools index $indelqualfile
  samtools flagstat $indelqualfile > ${sampleprefix}.flagstat.out
  """
}

process doalignmentlog {
  publishDir "$params.outdir/analysis", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '4 GB'

  input:
  file "logdir/*" from flagstatouts.toSortedList()

  output:
  file("alignment-summary.csv") into alignmentlogend

  script:
  """
  module load anaconda/Py2/python2
  python $HOME/CODE/core/utilities/logger.py logdir alignment-summary.csv flagstat
  """
}

forcall = indelqualforcall.join(samindex)
forcall.into {
  forcall1
  forcall2
}

process varcall {
  publishDir "$params.outdir/analysis", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '24 GB'

  input:
  set ( sampleprefix, file(indelqualfile), file(samindexfile) ) from forcall1
  file refs from ref4.first()

  output:
  set ( sampleprefix, file("${sampleprefix}.lofreq.vcf") ) into finishedcalls

  """
  module load LoFREQ/latest
  lofreq call -f ${refs}/${params.referencefile} -o ${sampleprefix}.lofreq.vcf --call-indels $indelqualfile
  """
}

//putting the bam and bai files ready to be handled all together for depth
(bam_for_depth_ch, bai_for_depth_ch) = forcall2.into(2)
bam_for_depth_ch = bam_for_depth_ch.map {it[1]}
bai_for_depth_ch = bai_for_depth_ch.map {it[2]}

process dodepth {
  publishDir "$params.outdir/alignments", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '50 GB'

  input:
  file("bamfiles/*") from bam_for_depth_ch.toSortedList()
  file("baifiles/*") from bai_for_depth_ch.toSortedList()

  output:
  file ( "merged_samtools.depth") into samdepthout

  """
  module load SAMTools/latest
  ln -s bamfiles/*.bam .
  ln -s baifiles/*.bai .
  bamfiles=`ls *.bam`
  samtools depth -aa -m 0 \$bamfiles > raw_samtools.depth
  echo Region Position `echo \$bamfiles | sed 's/_indelqual.bam//g'` > header.txt
  cat header.txt raw_samtools.depth > merged_samtools.depth
  """
}

process makevartable {
  publishDir "$params.outdir/analysis", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '24 GB'

  input:
  set ( sampleprefix, file(lofreqout) ) from finishedcalls

  output:
  set ( sampleprefix, file("${sampleprefix}-variants.csv") ) into nicetable

  """
  module load anaconda/Py2/python2
  python $HOME/CODE/core/utilities/tablefromvcf.py $lofreqout ${sampleprefix}-variants.csv
  """
}

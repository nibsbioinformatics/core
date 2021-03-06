//This is a nextflow script to be run with
//nextflow run cutlo.nf
//Performs basic cutadapt trimming, then alignment with bwa, then variant calling with lofreq

params.filepattern = "/usr/share/sequencing/miseq/output/161007_M01745_0131_000000000-ATN6R/Data/Intensities/BaseCalls/049*{_L001_R1_001,_L001_R2_001}.fastq.gz"
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

process doalignment {
  cpus 32
  queue 'WORK'
  time '12h'
  memory '10 GB'

  input:
  set ( sampleprefix, file(samples) ) from readpairs
  file refs from ref1.first()

  output:
  set (sampleprefix, file("${sampleprefix}.unsorted.sam") ) into samfile

  script:
  """
  module load BWA/latest
  bwa mem -t ${params.cpus} -R '@RG\\tID:${sampleprefix}\\tSM:${sampleprefix}\\tPL:Illumina' ${refs}/${params.referencefile} ${samples[0]} ${samples[1]} > ${sampleprefix}.unsorted.sam
  """
}

process sorttobam {
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

  """
  module load SAMTools/latest
  samtools index $indelqualfile
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

process dodepth {
  publishDir "$params.outdir/alignments", mode: "copy"
  cpus 1
  queue 'WORK'
  time '12h'
  memory '50 GB'

  input:
  set ( sampleprefix, file(indelqualfile), file(samindexfile) ) from forcall2

  output:
  set ( sampleprefix, file("${sampleprefix}.samtools.depth") ) into samdepthout

  """
  module load SAMTools/latest
  samtools depth -aa $indelqualfile > ${sampleprefix}.samtools.depth
  """
}





//This is a nextflow script to collect all read files from a directory then merge if needed, and do qc
//when running, use when to control merging dependent on nextseq or miseq parameter

params.mergelanes = false
params.indir = "/usr/share/sequencing/projects/272/raw_data"
params.qcdir = "/usr/share/sequencing/projects/272/qc-nf"


//merging four lanes only when params.mergelanes = true
if (params.mergelanes) {
  inputdirectory1 = file(params.indir)
  inputdirectory2 = file(params.indir)
} else {
  inputdirectory1 = Channel.empty()
  inputdirectory2 = Channel.empty()
}

process mergeforwardlanes {
  cpus 1
  queue 'WORK'
  time '12h'
  memory '4 GB'

  input:
  file(inputdir) from inputdirectory1

  output:
  file('*.forward.fastq.gz') into forwardfiles

  when:
  params.mergelanes

  """
  for samplename in `ls $inputdir | grep _L001_R1_001.fastq.gz | sed 's/_L001_R1_001.fastq.gz//g'`
  do
  cat $inputdir/\${samplename}_L001_R1_001.fastq.gz $inputdir/\${samplename}_L002_R1_001.fastq.gz $inputdir/\${samplename}_L003_R1_001.fastq.gz $inputdir/\${samplename}_L004_R1_001.fastq.gz > \${samplename}.forward.fastq.gz
  done
  """
}

process forwardsets {
  cpus 1
  queue 'WORK'
  time '12h'
  memory '4 GB'

  input:
  file(forwardfile) from forwardfiles.flatten()

  output:
  set ( val(sampleprefix), file("${sampleprefix}_L001_R1_001.fastq.gz") ) into forwardsets

  when:
  params.mergelanes

  script:
  sampleprefix = (forwardfile.name).replace(".forward.fastq.gz","")
  """
  basename=`echo $forwardfile | sed 's/.forward.fastq.gz//g'`
  mv $forwardfile \${basename}_L001_R1_001.fastq.gz
  """
}

process mergereverselanes {
  cpus 1
  queue 'WORK'
  time '12h'
  memory '4 GB'

  input:
  file(inputdir) from inputdirectory2

  output:
  file('*.reverse.fastq.gz') into reversefiles

  when:
  params.mergelanes

  """
  for samplename in `ls $inputdir | grep _L001_R2_001.fastq.gz | sed 's/_L001_R2_001.fastq.gz//g'`
  do
  cat $inputdir/\${samplename}_L001_R2_001.fastq.gz $inputdir/\${samplename}_L002_R2_001.fastq.gz $inputdir/\${samplename}_L003_R2_001.fastq.gz $inputdir/\${samplename}_L004_R2_001.fastq.gz > \${samplename}.reverse.fastq.gz
  done
  """
}

process reversesets {
  cpus 1
  queue 'WORK'
  time '12h'
  memory '4 GB'

  input:
  file(reversefile) from reversefiles.flatten()

  output:
  set ( val(sampleprefix), file("${sampleprefix}_L001_R2_001.fastq.gz") ) into reversesets

  when:
  params.mergelanes

  script:
  sampleprefix = (reversefile.name).replace(".reverse.fastq.gz","")
  """
  basename=`echo $reversefile | sed 's/.reverse.fastq.gz//g'`
  mv $reversefile \${basename}_L001_R2_001.fastq.gz
  """
}
//end of merging section

//conditionally readschannel is either a join from the forward and reverse sets, or it is just the channel from filepairs
if (params.mergelanes) {
  readschannel = forwardsets.join(reversesets)
} else {
  filepattern = params.indir + "/*{_L001_R1_001,_L001_R2_001}.fastq.gz"
  Channel.fromFilePairs(filepattern).set{readschannel}
}

readschannel.into {
  readsforfastqc
  readsforfastqscreen
}

process dofastqc {
  publishDir "$params.qcdir", mode: "copy"
  cpus 1
  queue 'WORK'
  time '8h'
  memory '10 GB'

  input:
  set ( sampleprefix, file(forwardreads), file(reversereads) ) from readsforfastqc

  output:
  set ( sampleprefix, file("${forwardhtml}"), file("${reversehtml}") ) into fastqchtmls

  script:
  forwardhtml = (forwardreads.name).replace(".fastq.gz","_fastqc.html")
  reversehtml = (reversereads.name).replace(".fastq.gz","_fastqc.html")
  """
  module load FastQC/latest
  fastqc $forwardreads
  fastqc $reversereads
  """
}

process dofastqscreen {
  publishDir "$params.qcdir", mode: "copy"
  cpus 8
  queue 'WORK'
  time '8h'
  memory '50 GB'

  input:
  set ( sampleprefix, file(forwardreads), file(reversereads) ) from readsforfastqscreen

  output:
  set ( sampleprefix, file("${forwardhtml}"), file("${reversehtml}") ) into fastqscreenhtmls

  script:
  forwardhtml = (forwardreads.name).replace(".fastq.gz","_screen.html")
  reversehtml = (reversereads.name).replace(".fastq.gz","_screen.html")
  """
  module load fastq-screen/0.13.0
  fastq_screen $forwardreads
  fastq_screen $reversereads
  """
}


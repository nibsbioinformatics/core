#!/bin/bash
#SBATCH -p WORK # partition (queue)
#SBATCH -N 1 # number of nodes
#SBATCH -n 1 # number of tasks
#SBATCH -c 16 # number of cpus per task
#SBATCH --mem 100 # memory pool for all cores in Gb
#SBATCH -t 23:30:30 # max time (HH:MM:SS)
#SBATCH -o slurm.%N.%j.out # STDOUT
#SBATCH -e slurm.%N.%j.err # STDERR

echo "### START - the job is starting at"
date
starttime=`date +"%s"`
echo
echo "the job is running on the node $SLURM_NODELIST"
echo "job number $SLURM_JOB_ID"
echo "STAT:jobName:$SLURM_JOB_ID\.out"
echo "STAT:exechosts:$SLURM_NODELIST"
echo

cd $PWD

sequencedate=$1 #200122
diroutput=$2 # /usr/share/sequencing/nextseq/output/200122_NB501506_0046_AH3CYJAFX2/

mkdir -p /usr/share/sequencing/nextseq/processed/${sequencedate}/InterOp
mkdir -p /usr/share/sequencing/nextseq/processed/${sequencedate}/log
mkdir -p /usr/share/sequencing/nextseq/processed/${sequencedate}/bcl2fastq


module load bcl2fastq/2.20

#Make sure that the appropriate sample sheet is at:
#/usr/share/sequencing/nextseq/processed/samplesheets/${sequencedate}_SampleSheet.csv

bcl2fastq --barcode-mismatches 0 -R $diroutput --interop-dir /usr/share/sequencing/nextseq/processed/${sequencedate}/InterOp --sample-sheet /usr/share/sequencing/nextseq/processed/samplesheets/${sequencedate}_SampleSheet.csv -o /usr/share/sequencing/nextseq/processed/${sequencedate}/bcl2fastq --no-lane-splitting > /usr/share/sequencing/nextseq/processed/${sequencedate}/log/bcl2fastq.out 2> /usr/share/sequencing/nextseq/processed/${sequencedate}/log/bcl2fastq.err

echo "####END job finished"
endtime=`date +"%s"`
duration=$((endtime - starttime))
echo "STAT:startTime:$starttime"
echo "STAT:doneTime:$endtime"
echo "STAT:runtime:$duration"
#!/bin/bash

GATK_RESOURCES=gs://hellbender-validation/resources/gatk-bundle

FILE=CEUTrio.HiSeq.WGS.b37.ch20.4m-6m.NA12878.bam

GCS_INPUT_PATH=gs://hellbender-validation/test-input/NA12878
GCS_OUTPUT_PATH=gs://hellbender-validation/pickard-gatk3-output/NA12878


cd /tmp/
gsutil cp ${GCS_INPUT_PATH}/${FILE}* ./
gsutil cp ${GATK_RESOURCES}/google.key ./
gsutil cp ${GATK_RESOURCES}/human_g1k_v37_decoy.dict ./
gsutil cp ${GATK_RESOURCES}/human_g1k_v37_decoy.fasta ./
gsutil cp ${GATK_RESOURCES}/human_g1k_v37_decoy.fasta.fai ./
gsutil cp ${GATK_RESOURCES}/dbsnp_138.b37.vcf* ./

# start the docker container and run the tools
sudo docker run -ti -e FILE=${FILE} -e REF=/host/tmp/human_g1k_v37_decoy.fasta \
  -e DBSNP=/host/tmp/dbsnp_138.b37.vcf \
  -e KEY=/host/tmp/google.key \
  -v /:/host gcr.io/atomic-life-89723/gga-3.4-0a bash

mkdir /tmp/gatk-validation/
cd /tmp/gatk-validation/

GATKJAR=/opt/extras/gatk/GenomeAnalysisTK.jar
SET_INTERVAL_RANGES=""

SUGGESTED_THREADS=8
SUGGESTED_RAM=48G # n1-standard-8 has 52GB total

FULL_INPUT=/host/tmp/${FILE}
FILE_WO_EXTENSION=`echo $FILE | sed 's/\.[^.]*$//'`
METRICS_FILE=/host/tmp/md-${FILE_WO_EXTENSION}.metrics
RECAL_TABLE=/host/tmp/recal-stats-${FILE_WO_EXTENSION}.txt
mkdir -p ./tmp
export TMPDIR=$(pwd)/tmp

##################
# MarkDuplicates #
##################
java -Xmx$SUGGESTED_RAM -Djava.io.tmpdir=${TMPDIR} -jar /opt/extras/picard-tools-1.130/picard.jar MarkDuplicates \
  ASSUME_SORTED=true \
  MAX_RECORDS_IN_RAM=2000000 \
  CREATE_INDEX=true \
  REMOVE_DUPLICATES=false \
  I=${FULL_INPUT} \
  O=/host/tmp/deduped-${FILE} \
  METRICS_FILE=${METRICS_FILE} \
  TMP_DIR=${TMPDIR}

####################
# BaseRecalibrator #
####################
#--useOriginalQualities shouldn't be necessary if it's a BAM reversion
java -Xmx$SUGGESTED_RAM -jar $GATKJAR -K $KEY -et NO_ET  \
  -T BaseRecalibrator \
  -nct $SUGGESTED_THREADS \
  -I ${FULL_INPUT} \
  -o $RECAL_TABLE \
  -R $REF \
  $SET_INTERVAL_RANGES \
    -knownSites $DBSNP \
  --useOriginalQualities \
  -DIQ \
  -cov ReadGroupCovariate \
  -cov QualityScoreCovariate \
  -cov CycleCovariate \
  -cov ContextCovariate

###################
# PrintReads BQSR #
###################
java -Xmx$SUGGESTED_RAM -jar $GATKJAR -K $KEY -et NO_ET \
  -T PrintReads \
  -I ${FULL_INPUT} \
  -R $REF \
  $SET_INTERVAL_RANGES \
    -BQSR $RECAL_TABLE \
  -o /host/tmp/recalibrated-${FILE} \
  -baq CALCULATE_AS_NECESSARY

# exit the docker container and copy back to gcs
exit

FILE_WO_EXTENSION=`echo $FILE | sed 's/\.[^.]*$//'`
gsutil cp deduped-${FILE_WO_EXTENSION}* ${GCS_OUTPUT_PATH}/
gsutil cp recal-stats-${FILE_WO_EXTENSION}.txt ${GCS_OUTPUT_PATH}/
gsutil cp recalibrated-${FILE}* ${GCS_OUTPUT_PATH}/
gsutil cp md-${FILE_WO_EXTENSION}.metrics ${GCS_OUTPUT_PATH}/



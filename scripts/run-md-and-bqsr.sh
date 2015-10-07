#!/bin/bash

FILE=CEUTrio.HiSeq.WGS.b37.ch20.4m-6m.NA12878.bam

GCS_INPUT_PATH=gs://hellbender-validation/test_inputs/NA12878/
GCS_OUTPUT_PATH=gs://hellbender-validation/pickard_gatk3_output/NA12878/

cd /tmp/
gsutil cp ${GCS_INPUT_PATH}${FILE}* ./

# start the docker container and run the tools
sudo docker run -ti -v /:/host gcr.io/atomic-life-89723/gga-3.4-0a bash
mkdir /tmp/gatk-validation/
cd /tmp/gatk-validation/


SUGGESTED_RAM=48G # n1-standard-8 has 52GB total
FULL_INPUT=`ls /host/tmp/*.bam`
FILE=`echo ${FULL_INPUT} | grep -o '[^/]*$'`

mkdir -p ./tmp
export TMPDIR=$(pwd)/tmp
java -Xmx$SUGGESTED_RAM -Djava.io.tmpdir=${TMPDIR} -jar /opt/extras/picard-tools-1.130/picard.jar MarkDuplicates \
  ASSUME_SORTED=true \
  MAX_RECORDS_IN_RAM=2000000 \
  CREATE_INDEX=true \
  METRICS_FILE=/dev/null \
  REMOVE_DUPLICATES=false \
  I=${FULL_INPUT} \
  O=/host/tmp/deduped-${FILE} \
  TMP_DIR=${TMPDIR}

# exit the docker container and copy back to gcs
exit

# copy doesn't work yet...
gsutil cp deduped-${FILE} ${GCS_OUTPUT_PATH}


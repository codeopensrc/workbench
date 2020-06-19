#!/bin/bash

while getopts "b:r:d:h:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
        r) REGION=$OPTARG;;
        h) HOST=$OPTARG;;
    esac
done


HOST_OPT=""
if [ -n "$HOST" ]; then HOST_OPT="-h $HOST"; fi

TODAY=$(date +"%F")

bash $HOME/code/scripts/db/dumpmongo.sh -d $DB_NAME $HOST_OPT

/usr/bin/aws s3 cp $HOME/code/backups/"$DB_NAME"_backups/"$DB_NAME"_$TODAY \
    s3://$BUCKET_NAME/"$DB_NAME"_backups/"$DB_NAME"_$TODAY --recursive --region $REGION

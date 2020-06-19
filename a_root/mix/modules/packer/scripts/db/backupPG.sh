#!/bin/bash

while getopts "b:r:d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
        r) REGION=$OPTARG;;
    esac
done


TODAY=$(date +"%F")

bash $HOME/code/scripts/db/dumppg.sh -d $DB_NAME -a

/usr/bin/aws s3 cp $HOME/code/backups/"$DB_NAME"_backups/"$DB_NAME"_$TODAY \
    s3://$BUCKET_NAME/"$DB_NAME"_backups/"$DB_NAME"_$TODAY --recursive --region $REGION

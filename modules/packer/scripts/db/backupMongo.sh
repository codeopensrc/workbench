#!/bin/bash

while getopts "a:b:d:h:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
        h) HOST=$OPTARG;;
    esac
done


HOST_OPT=""
if [ -n "$HOST" ]; then HOST_OPT="-h $HOST"; fi

TODAY=$(date +"%F")
YEAR_MONTH=$(date +"%Y-%m")

bash $HOME/code/scripts/db/dumpmongo.sh -d $DB_NAME $HOST_OPT

/usr/local/bin/mc cp $HOME/code/backups/"$DB_NAME"_backups/"$DB_NAME"_$TODAY \
    $S3_ALIAS/$S3_BUCKET_NAME/"$DB_NAME"_backups/$YEAR_MONTH --recursive

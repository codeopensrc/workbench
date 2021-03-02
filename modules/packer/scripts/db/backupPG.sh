#!/bin/bash

while getopts "a:b:d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
    esac
done


TODAY=$(date +"%F")
YEAR_MONTH=$(date +"%Y-%m")

bash $HOME/code/scripts/db/dumppg.sh -d $DB_NAME -a

/usr/local/bin/mc cp $HOME/code/backups/"$DB_NAME"_backups/"$DB_NAME"_$TODAY \
    $S3_ALIAS/$S3_BUCKET_NAME/"$DB_NAME"_backups/$YEAR_MONTH --recursive

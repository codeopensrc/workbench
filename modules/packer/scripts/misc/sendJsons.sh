#!/bin/bash

while getopts "a:b:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
    esac
done

TODAY=$(date +"%Y-%m-%d")

cd $HOME/code

#Bundle JSONS
tar czf "jsons_$TODAY.tar.gz" jsons
tar czf "csv_$TODAY.tar.gz" csv

#Upload JSON
/usr/local/bin/mc cp $HOME/code/"jsons_$TODAY.tar.gz" \
  $S3_ALIAS/$S3_BUCKET_NAME/json_backups/"jsons_$TODAY.tar.gz"
/usr/local/bin/mc cp $HOME/code/"csv_$TODAY.tar.gz" \
  $S3_ALIAS/$S3_BUCKET_NAME/csv_backups/"csv_$TODAY.tar.gz"

#Remove files
rm -r $HOME/code/"jsons_$TODAY.tar.gz"
rm -r $HOME/code/jsons/*
rm -r $HOME/code/"csv_$TODAY.tar.gz"
rm -r $HOME/code/csv/*

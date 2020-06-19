#!/bin/bash

while getopts "b:r:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BUCKET_NAME=$OPTARG;;
        r) REGION=$OPTARG;;
    esac
done

TODAY=$(date +"%Y-%m-%d")

cd $HOME/code

#Bundle JSONS
tar czf "jsons_$TODAY.tar.gz" jsons
tar czf "csv_$TODAY.tar.gz" csv

#Upload JSON
/usr/bin/aws s3 cp $HOME/code/"jsons_$TODAY.tar.gz" \
  s3://$BUCKET_NAME/json_backups/"jsons_$TODAY.tar.gz" --region $REGION
/usr/bin/aws s3 cp $HOME/code/"csv_$TODAY.tar.gz" \
  s3://$BUCKET_NAME/csv_backups/"csv_$TODAY.tar.gz" --region $REGION

#Remove files
rm -r $HOME/code/"jsons_$TODAY.tar.gz"
rm -r $HOME/code/jsons/*
rm -r $HOME/code/"csv_$TODAY.tar.gz"
rm -r $HOME/code/csv/*

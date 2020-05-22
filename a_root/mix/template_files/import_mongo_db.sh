#!/bin/bash

while getopts "b:r:d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
        r) REGION=$OPTARG;;
    esac
done

if [[ -z $BUCKET_NAME ]]; then echo "Please provide s3 bucket name using -b BUCKET"; exit ; fi
if [[ -z $DB_NAME ]]; then echo "Please provide DB name using -d DB_NAME"; exit ; fi
if [[ -z $REGION ]]; then echo "Please provide region using -r REGION"; exit ; fi

for i in {0..20}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    echo "Checking $DATE";
    aws s3 ls s3://"$BUCKET_NAME"/"$DB_NAME"_backups/"$DB_NAME"_$DATE/$DB_NAME --region $REGION;
    if [[ $? == 0 ]]; then
        echo "Downloading s3://"$BUCKET_NAME"/"$DB_NAME"_backups/"$DB_NAME"_$DATE/"$DB_NAME" into ~/code/backups";
        aws s3 cp s3://"$BUCKET_NAME"/"$DB_NAME"_backups/"$DB_NAME"_$DATE/$DB_NAME \
            ~/code/backups/"$DB_NAME"_$DATE/$DB_NAME --recursive --region $REGION;
        echo "Importing ~/code/backups/"$DB_NAME"_$DATE/$DB_NAME into mongo";
        mongorestore --db $DB_NAME ~/code/backups/"$DB_NAME"_$DATE/$DB_NAME
        exit;
    fi
done

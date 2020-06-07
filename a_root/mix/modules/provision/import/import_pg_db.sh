#!/bin/bash

PROFILE=default

while getopts "b:r:p:d:u:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
        r) REGION=$OPTARG;;
        p) PROFILE=$OPTARG;;
        u) DB_USER=$OPTARG;;
    esac
done

POSTGRES_USER=postgres
if [[ $DB_USER != "" ]]; then POSTGRES_USER=$DB_USER; fi


if [[ -z $BUCKET_NAME ]]; then echo "Please provide s3 bucket name using -b BUCKET"; exit ; fi
if [[ -z $DB_NAME ]]; then echo "Please provide DB name using -d DB_NAME"; exit ; fi
if [[ -z $REGION ]]; then echo "Please provide region using -r REGION"; exit ; fi

for i in {0..20}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    echo "Checking $DATE";
    aws --profile $PROFILE s3 ls s3://"$BUCKET_NAME"/"$DB_NAME"_backups/"$DB_NAME"_$DATE/$DB_NAME.gz --region $REGION;
    if [[ $? == 0 ]]; then
        echo "Downloading s3://"$BUCKET_NAME"/"$DB_NAME"_backups/"$DB_NAME"_$DATE/"$DB_NAME".gz into ~/code/backups";
        aws --profile $PROFILE s3 cp s3://"$BUCKET_NAME"/"$DB_NAME"_backups/"$DB_NAME"_$DATE/$DB_NAME.gz ~/code/backups/"$DB_NAME"_$DATE/$DB_NAME.gz --region $REGION;
        echo "Create DB $DB_NAME";
        createdb -T template0 -U $POSTGRES_USER $DB_NAME;
        echo "Importing ~/code/backups/"$DB_NAME"_$DATE/$DB_NAME.gz into postgres";
        gunzip -c ~/code/backups/"$DB_NAME"_$DATE/$DB_NAME.gz | psql -U $POSTGRES_USER -d $DB_NAME;
        exit;
    fi
done

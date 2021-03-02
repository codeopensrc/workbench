#!/bin/bash

while getopts "a:b:h:d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
        h) HOST=$OPTARG;;
    esac
done

if [[ -z $S3_ALIAS ]]; then echo "Please provide s3 alias using -a S3_ALIAS"; exit ; fi
if [[ -z $S3_BUCKET_NAME ]]; then echo "Please provide s3 bucket name using -b S3_BUCKET_NAME"; exit ; fi
if [[ -z $DB_NAME ]]; then echo "Please provide DB name using -d DB_NAME"; exit ; fi

for i in {0..20}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/${DB_NAME}_backups/${YEAR_MONTH}/${DB_NAME}_${DATE}/${DB_NAME}/"
    LOCAL_FILE="$HOME/code/backups/${DB_NAME}_backups/${DB_NAME}_${DATE}/${DB_NAME}"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE --recursive;

        echo "Importing $LOCAL_FILE into mongo";
        if [ -n $HOST ]; then
            mongorestore --host $HOST --db $DB_NAME $LOCAL_FILE
        else
            mongorestore --db $DB_NAME $LOCAL_FILE
        fi
        exit;
    fi
done

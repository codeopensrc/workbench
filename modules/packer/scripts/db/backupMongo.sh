#!/bin/bash

while getopts "a:b:d:h:ce" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
        c) USE_CONSUL=true;;
        d) DB_NAME=$OPTARG;;
        h) HOST=$OPTARG;;
        e) ENCRYPT="-e";;
    esac
done


HOST_OPT=""
if [ -n "$HOST" ]; then HOST_OPT="-h $HOST"; fi

TODAY=$(date +"%F")
YEAR_MONTH=$(date +"%Y-%m")

bash $HOME/code/scripts/db/dumpmongo.sh -d $DB_NAME $HOST_OPT $ENCRYPT

/usr/local/bin/mc cp $HOME/code/backups/${DB_NAME}_backups/${DB_NAME}_${TODAY} \
    ${S3_ALIAS}/${S3_BUCKET_NAME}/${DB_NAME}_backups/${YEAR_MONTH} --recursive

UPLOAD_EXIT_CODE=$?

CHECK_ID=${DB_NAME}
SERVICE_ID="mongo_backup"
TTL="24h5m"

### Register service and checks to display recent backups
if [[ $USE_CONSUL == true ]]; then
    bash $HOME/code/scripts/misc/update_backup_status.sh -c $CHECK_ID -s $SERVICE_ID -e $UPLOAD_EXIT_CODE -t $TTL
fi

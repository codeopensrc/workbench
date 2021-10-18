#!/bin/bash

TODAY=$(date +"%Y-%m-%d")

while getopts "d:h:e" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DB=$OPTARG;;
        h) HOST=$OPTARG;;
        e) ENCRYPT=true;;
    esac
done

HOST_OPT=""
if [ -n "$HOST" ]; then HOST_OPT="--host $HOST"; fi


if [ -n "$DB" ]; then
    BACKUP_DIR=$HOME/code/backups/${DB}_backups/${DB}_${TODAY}
    BACKUP_FILE=$BACKUP_DIR/${DB}_${TODAY}.tar.gz
    mkdir -p $BACKUP_DIR
    mongodump --db $DB $HOST_OPT --out $BACKUP_DIR/
    (cd $BACKUP_DIR && tar -czvf $BACKUP_FILE ${DB})
    rm -rf $BACKUP_DIR/$DB
else
    BACKUP_DIR=$HOME/code/backups/mongo_backups/mongo_full_${TODAY}
    BACKUP_FILE=$BACKUP_DIR/mongo_full_${TODAY}.tar.gz
    mkdir -p $BACKUP_DIR
    mongodump $HOST_OPT --out $BACKUP_DIR/
    (cd $BACKUP_DIR && tar -czvf $BACKUP_FILE *)
    rm -rf $BACKUP_DIR/*
fi


if [[ -n $ENCRYPT ]]; then
    bash $HOME/code/scripts/misc/encrypt.sh -f $BACKUP_FILE
    rm $BACKUP_FILE
fi

echo "Backup completed : "  $(date)

#!/bin/bash

TODAY=$(date +"%Y-%m-%d")

while getopts "d:h:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DB=$OPTARG;;
        h) HOST=$OPTARG;;
    esac
done

HOST_OPT=""
if [ -n "$HOST" ]; then HOST_OPT="--host $HOST"; fi


if [ -n "$DB" ]; then
    mongodump --db $DB $HOST_OPT --out $HOME/code/backups/"$DB"_backups/"$DB"_"$TODAY"/
else
    mongodump $HOST_OPT --out $HOME/code/backups/mongo_backups/mongo_full_"$TODAY"/
fi
echo "Backup completed : "  $(date)

#!/bin/bash

TODAY=$(date +"%Y-%m-%d")

while getopts "d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DB=$OPTARG;;
    esac
done

if [ -n "$DB" ]; then
    mongodump --db $DB --out $HOME/code/backups/"$DB"_backups/"$DB"_"$TODAY"/
else
    mongodump --out $HOME/code/backups/mongo_backups/mongo_full_"$TODAY"/
fi
echo "Backup completed : "  $(date)

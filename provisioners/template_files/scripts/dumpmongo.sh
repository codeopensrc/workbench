#!/bin/bash

TODAY=$(date +"%Y-%m-%d")

while getopts "d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DB=$OPTARG;;
    esac
done

if [ -z "$DB" ]; then
     echo "Please specify a database to dump from mongo: -d DBNAME"
     exit;
fi


mongodump --db $DB --out $HOME/code/backups/"$DB"_backups/"$DB"_"$TODAY"/

echo "Backup completed : "  $(date)

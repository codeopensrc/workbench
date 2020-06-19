#!/bin/bash

TODAY=$(date +"%Y-%m-%d")

while getopts "d:u:a" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) ALL="true";;
        d) DB=$OPTARG;;
        u) DB_USER=$OPTARG;;
    esac
done

if [ -z "$DB" ]; then
     echo "Please specify a database to dump from pg: -d DBNAME"
     exit;
fi

POSTGRES_USER=postgres
if [[ $DB_USER != "" ]]; then POSTGRES_USER=$DB_USER; fi

mkdir -p $HOME/code/backups/"$DB"_backups/"$DB"_"$TODAY"
pg_dump -d $DB -U $POSTGRES_USER -O -x | gzip > $HOME/code/backups/"$DB"_backups/"$DB"_"$TODAY"/"$DB"_noowner.gz

if [ "$ALL" == "true" ]; then
    pg_dumpall -U $POSTGRES_USER | gzip > $HOME/code/backups/"$DB"_backups/"$DB"_"$TODAY"/$DB.gz
fi

echo "Backup completed : "  $(date)

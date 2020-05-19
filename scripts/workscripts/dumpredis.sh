#!/bin/bash

TODAY=$(date +"%Y-%m-%d")

while getopts "d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DB=$OPTARG;;
    esac
done

if [ -z "$DB" ]; then
     echo "Please specify a database to dump from redis: -d DBNAME"
     exit;
fi

mkdir -p $HOME/code/backups/"$DB"_backups/"$DB"_"$TODAY"
/usr/local/bin/redis-cli save
sudo cp /var/lib/redis/dump.rdb $HOME/code/backups/"$DB"_backups/"$DB"_"$TODAY"/$DB.rdb

echo "Backup completed : "  $(date)

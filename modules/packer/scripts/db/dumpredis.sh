#!/bin/bash

TODAY=$(date +"%Y-%m-%d")

while getopts "d:e" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DB=$OPTARG;;
        e) ENCRYPT=true;;
    esac
done

if [ -z "$DB" ]; then
     echo "Please specify a database to dump from redis: -d DBNAME"
     exit;
fi

mkdir -p $HOME/code/backups/${DB}_backups/${DB}_${TODAY}
/usr/local/bin/redis-cli save
sudo cp /var/lib/redis/dump.rdb $HOME/code/backups/${DB}_backups/${DB}_${TODAY}/${DB}.rdb

if [[ -n $ENCRYPT ]]; then
    bash $HOME/code/scripts/misc/encrypt.sh -f $HOME/code/backups/${DB}_backups/${DB}_${TODAY}/${DB}.rdb
    rm $HOME/code/backups/${DB}_backups/${DB}_${TODAY}/${DB}.rdb
fi

echo "Backup completed : "  $(date)

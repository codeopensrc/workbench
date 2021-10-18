#!/bin/bash

while getopts "d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DB=$OPTARG;;
    esac
done

if [ -z "$DB" ]; then
     echo "Please specify a database: -d DBNAME"
     exit;
fi

## Removes 7 days worth starting from 2 days prior (keeps latest backup)
for NUM in {2..8}; do
    DAY=$(date -d "-$NUM days" +"%Y-%m-%d")
    #echo "Removing $HOME/code/backups/${DB}_backups/${DB}_${DAY}"
    rm -rf $HOME/code/backups/${DB}_backups/${DB}_${DAY}
done

#!/bin/bash

while getopts "d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DB=$OPTARG;;
    esac
done

FRI=$(date -d "-8 days" +"%Y-%m-%d")
MON=$(date -d "-5 days" +"%Y-%m-%d")
TUES=$(date -d "-4 days" +"%Y-%m-%d")
WED=$(date -d "-3 days" +"%Y-%m-%d")
THURS=$(date -d "-2 days" +"%Y-%m-%d")

if [ -z "$DB" ]; then
     echo "Please specify a database: -d DBNAME"
     exit;
fi

rm -rf $HOME/code/backups/${DB}_backups/${DB}_${FRI}
rm -rf $HOME/code/backups/${DB}_backups/${DB}_${MON}
rm -rf $HOME/code/backups/${DB}_backups/${DB}_${TUES}
rm -rf $HOME/code/backups/${DB}_backups/${DB}_${WED}
rm -rf $HOME/code/backups/${DB}_backups/${DB}_${THURS}

#!/bin/bash

while getopts "d:u:f:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DB=$OPTARG;;
        u) DB_USER=$OPTARG;;
        f) PSQL_FN=$OPTARG;;
    esac
done

if [ -z "$DB" ]; then
     echo "Please specify a database to dump from pg: -d DBNAME"
     exit;
fi

if [[ -z $PSQL_FN ]]; then echo "Please provide psql function: -f 'psqlFunction()'"; exit ; fi

POSTGRES_USER=postgres
if [[ $DB_USER != "" ]]; then POSTGRES_USER=$DB_USER; fi

/usr/bin/psql -U $POSTGRES_USER -d $DB -c 'SELECT * FROM '${PSQL_FN}';'

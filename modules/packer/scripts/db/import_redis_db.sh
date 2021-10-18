#!/bin/bash

while getopts "a:b:d:p:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
        p) PASSPHRASE_FILE=$OPTARG;;
    esac
done


if [[ -z $S3_ALIAS ]]; then echo "Please provide s3 alias using -a S3_ALIAS"; exit ; fi
if [[ -z $S3_BUCKET_NAME ]]; then echo "Please provide s3 bucket name using -b S3_BUCKET_NAME"; exit ; fi
if [[ -z $DB_NAME ]]; then echo "Please provide DB name using -d DB_NAME"; exit ; fi

GPG_EXT=""
if [[ -n $PASSPHRASE_FILE ]]; then GPG_EXT=".gpg"; fi

for i in {0..20}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/${DB_NAME}_backups/${YEAR_MONTH}/${DB_NAME}_${DATE}/${DB_NAME}.rdb${GPG_EXT}"
    LOCAL_FILE="$HOME/code/backups/${DB_NAME}_backups/${DB_NAME}_${DATE}/${DB_NAME}.rdb${GPG_EXT}"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        echo "Stopping Redis";
        sudo service redis_6379 stop
        sudo mv /var/lib/redis/dump.rdb /var/lib/redis/dump.rdb.old
        sudo mv /var/lib/redis/*.aof /var/lib/redis/appendonly.aof.old ## In case aof enabled

        # If we're using AOF
        # Look for redis config, disable aof using sed
        #  - /etc/redis/redis.conf
        #  - change "appendonly yes" to "appendonly no"

        if [[ -n $PASSPHRASE_FILE ]]; then
            ENCRYPTED_FILE=$LOCAL_FILE
            LOCAL_FILE=${ENCRYPTED_FILE//$GPG_EXT/}
            echo "Decrypting $ENCRYPTED_FILE to $LOCAL_FILE"
            gpg --output $LOCAL_FILE --passphrase-fd 0 --pinentry-mode loopback --batch --decrypt $ENCRYPTED_FILE < $PASSPHRASE_FILE
            rm $ENCRYPTED_FILE
        fi

        echo "Importing $LOCAL_FILE into redis";
        sudo mv $LOCAL_FILE /var/lib/redis/dump.rdb

        # sudo chown redis:redis /var/lib/redis/dump.rdb
        sudo chmod 660 /var/lib/redis/dump.rdb

        echo "Starting Redis";
        sudo service redis_6379 start

        # If we're using AOF
        # redis cli BGREWRITEAOF
        # sudo service redis-server stop

        # Look for redis config, enable aof using sed
        #  - /etc/redis/redis.conf
        #  - change "appendonly no" to "appendonly yes"

        # sudo service redis-server start


        exit;
    fi
done

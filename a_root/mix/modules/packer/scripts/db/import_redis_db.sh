#!/bin/bash

while getopts "b:r:d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
        r) REGION=$OPTARG;;
    esac
done


if [[ -z $BUCKET_NAME ]]; then echo "Please provide s3 bucket name using -b BUCKET"; exit ; fi
if [[ -z $DB_NAME ]]; then echo "Please provide DB name using -d DB_NAME"; exit ; fi
if [[ -z $REGION ]]; then echo "Please provide region using -r REGION"; exit ; fi


for i in {0..20}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    echo "Checking $DATE";
    aws s3 ls s3://"$BUCKET_NAME"/"$DB_NAME"_backups/"$DB_NAME"_$DATE/$DB_NAME.rdb --region $REGION;
    if [[ $? == 0 ]]; then
        echo "Downloading s3://"$BUCKET_NAME"/"$DB_NAME"_backups/"$DB_NAME"_$DATE/"$DB_NAME".rdb into ~/code/backups";
        aws s3 cp s3://"$BUCKET_NAME"/"$DB_NAME"_backups/"$DB_NAME"_$DATE/$DB_NAME.rdb ~/code/backups/"$DB_NAME"_$DATE/$DB_NAME.rdb --region $REGION;
        echo "Create DB $DB_NAME";


        sudo service redis_6379 stop
        sudo mv /var/lib/redis/dump.rdb /var/lib/redis/dump.rdb.old
        sudo mv /var/lib/redis/*.aof /var/lib/redis/appendonly.aof.old ## In case aof enabled

        # If we're using AOF
        # Look for redis config, disable aof using sed
        #  - /etc/redis/redis.conf
        #  - change "appendonly yes" to "appendonly no"

        echo "Importing ~/code/backups/"$DB_NAME"_$DATE/$DB_NAME.rdb into redis";

        sudo cp -p ~/code/backups/"$DB_NAME"_$DATE/$DB_NAME.rdb /var/lib/redis/dump.rdb
        # sudo chown redis:redis /var/lib/redis/dump.rdb
        sudo chmod 660 /var/lib/redis/dump.rdb

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

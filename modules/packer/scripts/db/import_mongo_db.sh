#!/bin/bash

while getopts "a:b:h:d:p:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
        d) DB_NAME=$OPTARG;;
        h) HOST=$OPTARG;;
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

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/${DB_NAME}_backups/${YEAR_MONTH}/${DB_NAME}_${DATE}/${DB_NAME}_${DATE}.tar.gz${GPG_EXT}"
    LOCAL_FILE="$HOME/code/backups/${DB_NAME}_backups/${DB_NAME}_${DATE}/${DB_NAME}_${DATE}.tar.gz${GPG_EXT}"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        if [[ -n $PASSPHRASE_FILE ]]; then
            ENCRYPTED_FILE=$LOCAL_FILE
            LOCAL_FILE=${ENCRYPTED_FILE//$GPG_EXT/}
            echo "Decrypting $ENCRYPTED_FILE to $LOCAL_FILE"
            gpg --output $LOCAL_FILE --passphrase-fd 0 --pinentry-mode loopback --batch --decrypt $ENCRYPTED_FILE < $PASSPHRASE_FILE
            rm $ENCRYPTED_FILE
        fi

        DB_FILE=${LOCAL_FILE//_${DATE}.tar.gz/}
        mkdir -p $DB_FILE
        tar -xzvf $LOCAL_FILE -C $DB_FILE --strip-components=1
        rm $LOCAL_FILE

        echo "Importing $DB_FILE into mongo";
        if [ -n $HOST ]; then
            mongorestore --host $HOST --db $DB_NAME $DB_FILE
        else
            mongorestore --db $DB_NAME $DB_FILE
        fi

        rm -rf $DB_FILE

        exit;
    fi
done

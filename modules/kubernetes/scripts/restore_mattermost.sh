#!/bin/bash


while getopts "a:b:k:s:r:f:u:p:n:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
        k) S3_ACCESS_KEY=$OPTARG;;
        s) S3_SECRET_KEY=$OPTARG;;
        r) S3_REGION=$OPTARG;;
        f) FILE_NAME=$OPTARG;;
        u) DB_USER=$OPTARG;;
        p) DB_PASS=$OPTARG;;
        n) NEW_LOCATION=$OPTARG;;
        #v) OPT_VERSION=${OPTARG}_;;
        #p) PASSPHRASE_FILE=$OPTARG;;
    esac
done

apt-get update
apt-get install -y curl

BACKUP_FOLDER_LOCATION=${S3_ALIAS}/${S3_BUCKET_NAME}/mattermost
RESTORE_TO_LOCATION=${S3_ALIAS}/${NEW_LOCATION}

if [[ ! -f /usr/local/bin/mc ]]; then
    curl https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
    chmod +x /usr/local/bin/mc

    # add aws mc alias
    if [[ $S3_ALIAS == "aws" ]]; then
      mc alias set s3 https://s3.amazonaws.com $S3_ACCESS_KEY $S3_SECRET_KEY 
    fi
    
    # add do mc alias
    if [[ $S3_ALIAS == "spaces" ]]; then
      mc alias set spaces https://${S3_REGION}.digitaloceanspaces.com $S3_ACCESS_KEY $S3_SECRET_KEY 
    fi
fi

## Mattermost data
for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${BACKUP_FOLDER_LOCATION}/${YEAR_MONTH}/mattermost_data_${DATE}.tar.gz${GPG_EXT}"
    LOCAL_FILE="mattermost_data_${DATE}.tar.gz${GPG_EXT}"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then

        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        TODAY=$(date +"%F")
        MATTERMOST_DIR=./mattermost
        mkdir -p $MATTERMOST_DIR

        if [[ -n $PASSPHRASE_FILE ]]; then
            ENCRYPTED_FILE=$LOCAL_FILE
            LOCAL_FILE=${ENCRYPTED_FILE//$GPG_EXT/}
            echo "Decrypting $ENCRYPTED_FILE to $LOCAL_FILE"
            gpg --output $LOCAL_FILE --passphrase-fd 0 --pinentry-mode loopback --batch --decrypt $ENCRYPTED_FILE < $PASSPHRASE_FILE
            rm $ENCRYPTED_FILE
        fi

        ## TODO: Was used to backup current before restoring as a fallback 
        #(cd $MATTERMOST_DIR/ && tar -czvf $MATTERMOST_DIR/mattermost_data_$TODAY.tar.gz *)
        tar -xzvf $LOCAL_FILE -C $MATTERMOST_DIR

        ## TODO: How should we handle files that already exist at the bucket location
        /usr/local/bin/mc mirror --exclude "mattermost*" $MATTERMOST_DIR/ ${RESTORE_TO_LOCATION};

        rm $LOCAL_FILE

        break
    fi
done

## Mattermost db
for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${BACKUP_FOLDER_LOCATION}/${YEAR_MONTH}/mattermost_dbdump_${DATE}.sql.gz${GPG_EXT}"
    LOCAL_FILE="mattermost_dbdump_${DATE}.sql.gz${GPG_EXT}"

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

        apt-get install -y postgresql-client
        gunzip -c $LOCAL_FILE | psql postgres://$DB_USER:$DB_PASS@postgresql:5432/mattermost

        rm $LOCAL_FILE

        break
    fi
done

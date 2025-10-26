#!/bin/bash

while getopts "a:b:k:r:s:m:n:u:p:v:e" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) MAIN_BACKUP_BUCKET=$OPTARG;;
        k) S3_ACCESS_KEY=$OPTARG;;
        r) S3_REGION=$OPTARG;;
        s) S3_SECRET_KEY=$OPTARG;;
        m) S3_SRC_ENV_BACKUP_BUCKET_PREFIX=$OPTARG;;
        n) S3_TARGET_ENV_BACKUP_BUCKET_PREFIX=$OPTARG;;
        u) DB_USER=$OPTARG;;
        p) DB_PASS=$OPTARG;;
        v) OPT_VERSION=${OPTARG}_;;
        e) ENCRYPT=true;;
    esac
done

apt-get update
apt-get install -y curl

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


TODAY=$(date +"%F")
YEAR_MONTH=$(date +"%Y-%m")

DOW=$(date +"%w")
SUNDAY=$(date -d "-$DOW days" +"%Y-%m-%d")
SUNDAY_YEAR_MONTH=$(date -d "-$DOW days" +"%Y-%m")

# These are here for illustration purposes
# Last weeks Mon
MON=$(date -d "last Mon" +"%Y-%m-%d")
# Next weeks Tues
TUES=$(date -d "next Tues" +"%Y-%m-%d")
# Todays date if Wednesday OR next weeks Wednesday
WED=$(date -d "Wed" +"%Y-%m-%d")


## mirror from main objectstore to alt objectstore
## TODO: We're restoring from backup zips so not really necessary compared to gitlab using objectstore + backups
#/usr/local/bin/mc mirror $S3_ALIAS/${S3_SRC_ENV_BACKUP_BUCKET_PREFIX}-mattermost $S3_ALIAS/${S3_TARGET_ENV_BACKUP_BUCKET_PREFIX}-mattermost


MAIN_BACKUP_FOLDER=$HOME/mattermost-backups
ZIP_FILE_NAME=mattermost_data_$TODAY.tar.gz
DB_DUMP_NAME=mattermost_dbdump_$TODAY.sql.gz 

mkdir -p $MAIN_BACKUP_FOLDER

## cp down
mattermost_folders=(client-plugins data plugins users)
for folder in "${mattermost_folders[@]}"; do
    echo "Copy $S3_ALIAS/${S3_SRC_ENV_BACKUP_BUCKET_PREFIX}-mattermost/$folder to $MAIN_BACKUP_FOLDER/$folder"
    /usr/local/bin/mc cp $S3_ALIAS/${S3_SRC_ENV_BACKUP_BUCKET_PREFIX}-mattermost/$folder $MAIN_BACKUP_FOLDER/$folder --recursive
done

## Think our config comes from helm env vars mainly atm
## TODO: Verify works without/with config.json
#mc cp ${S3_SRC_ENV_BACKUP_BUCKET_PREFIX}-mattermost/config.json $MAIN_BACKUP_FOLDER/config.json

## tar
tar -czvf $ZIP_FILE_NAME $MAIN_BACKUP_FOLDER 

## cp to backup bucket
/usr/local/bin/mc cp $ZIP_FILE_NAME $S3_ALIAS/$MAIN_BACKUP_BUCKET/mattermost/$YEAR_MONTH/


## OLD   -  Copy down object store, tar, mc cp up to backup bucket
#(cd /var/opt/gitlab/mattermost/ && tar -czvf $HOME/code/backups/mattermost/mattermost_data_$TODAY.tar.gz *)



### DB

## Add official postgres apt repo to get more up-to-date postgres client version
apt-get install -y curl ca-certificates gnupg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(. /etc/os-release ; echo $VERSION_CODENAME)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

apt-get update
apt-get install -y postgresql-client-17

PGPASSWORD=$DB_PASS pg_dump -h postgresql -U $DB_USER -d mattermost | gzip > $DB_DUMP_NAME

/usr/local/bin/mc cp $DB_DUMP_NAME $S3_ALIAS/$MAIN_BACKUP_BUCKET/mattermost/$YEAR_MONTH/

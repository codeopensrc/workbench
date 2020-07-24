#!/bin/bash

### Misc backup info

### Backup procedures
### https://docs.gitlab.com/omnibus/settings/backups.html

### Backup configs
# gitlab-ctl backup-etc && cd /etc/gitlab/config_backup && cp $(ls -t | head -n1) /secret/gitlab/backups/

OPT_VERSION=""

while getopts "b:r:v:cf" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BUCKET_NAME=$OPTARG;;
        c) GC_DOCKER_REGISTRY=true;;
        f) FILE_NAME=$OPTARG;;
        r) REGION=$OPTARG;;
        v) OPT_VERSION=${OPTARG}_;;
    esac
done


if [[ -z $BUCKET_NAME ]]; then echo "Please provide s3 bucket name using -b BUCKET"; exit ; fi
# if [[ -z $FILE_NAME ]]; then echo "Please provide file name using -f FILE_NAME"; exit ; fi
if [[ -z $REGION ]]; then echo "Please provide region using -r REGION"; exit ; fi


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


###!###!###!###!###!###!###!###!###!###!###!
###! Everything below performs the Backup
###!###!###!###!###!###!###!###!###!###!###!

mkdir -p $HOME/code/backups/letsencrypt
(cd /etc/ && tar -czvf $HOME/code/backups/letsencrypt/letsencrypt_$TODAY.tar.gz letsencrypt)
mkdir -p $HOME/code/backups/ssh_keys
(cd /etc/ssh/ && tar -czvf $HOME/code/backups/ssh_keys/ssh_keys_$TODAY.tar.gz ssh_host_*_key*)
gitlab-backup create BACKUP=dump GZIP_RSYNCABLE=yes
# CRON=1 suppresses output
# gitlab-backup create BACKUP=dump GZIP_RSYNCABLE=yes CRON=1
mkdir -p $HOME/code/backups/mattermost
(cd /var/opt/gitlab/mattermost/ && tar -czvf $HOME/code/backups/mattermost/mattermost_data_$TODAY.tar.gz *)
sudo -i -u gitlab-psql -- /opt/gitlab/embedded/bin/pg_dump -h /var/opt/gitlab/postgresql mattermost_production | gzip > $HOME/code/backups/mattermost/mattermost_dbdump_$TODAY.sql.gz


# Upload
/usr/bin/aws s3 cp $HOME/code/backups/letsencrypt/letsencrypt_$TODAY.tar.gz \
    s3://$BUCKET_NAME/admin_backups/letsencrypt_backups/$YEAR_MONTH/letsencrypt_$TODAY.tar.gz --region $REGION

/usr/bin/aws s3 cp $HOME/code/backups/ssh_keys/ssh_keys_$TODAY.tar.gz \
    s3://$BUCKET_NAME/admin_backups/ssh_keys_backups/$YEAR_MONTH/ssh_keys_$TODAY.tar.gz --region $REGION

/usr/bin/aws s3 cp $HOME/code/backups/mattermost/mattermost_data_$TODAY.tar.gz \
    s3://$BUCKET_NAME/admin_backups/mattermost_backups/$YEAR_MONTH/mattermost_data_$TODAY.tar.gz --region $REGION

/usr/bin/aws s3 cp $HOME/code/backups/mattermost/mattermost_dbdump_$TODAY.sql.gz \
    s3://$BUCKET_NAME/admin_backups/mattermost_backups/$YEAR_MONTH/mattermost_dbdump_$TODAY.sql.gz --region $REGION

# The goal is to rsync over the previous days and keep snapshot once a week instead of storing a daily multi gig backup
/usr/bin/aws s3 cp /var/opt/gitlab/backups/dump_gitlab_backup.tar \
    s3://$BUCKET_NAME/admin_backups/gitlab_backups/$SUNDAY_YEAR_MONTH/dump_gitlab_backup_${OPT_VERSION}$SUNDAY.tar --region $REGION

# Dont keep secrets backup on server I guess? Directly upload the single json file
/usr/bin/aws s3 cp /etc/gitlab/gitlab-secrets.json \
    s3://$BUCKET_NAME/admin_backups/gitlab_backups/$SUNDAY_YEAR_MONTH/gitlab-secrets_${OPT_VERSION}$SUNDAY.json --region $REGION


# Cleanup every Sunday
if [[ "$TODAY" == "$SUNDAY" ]]; then
    rm -rf $HOME/code/backups/letsencrypt/*
    rm -rf $HOME/code/backups/ssh_keys/*
    rm -rf $HOME/code/backups/mattermost/*

    if [[ "$GC_DOCKER_REGISTRY" == true ]]; then
        # https://gitlab.com/help/administration/packages/container_registry.md#container-registry-garbage-collection
        sudo gitlab-ctl registry-garbage-collect -m

        # TODO: No Downtime with below link instructions(above cmd with -m flag ran for 1 second)
        # https://gitlab.com/help/administration/packages/container_registry.md#performing-garbage-collection-without-downtime
    fi
fi




### MISC Downgrading gitlab to earlier version
# https://docs.gitlab.com/omnibus/update/README.html#reverting-to-gitlab-6.6.x-or-later

# sudo gitlab-ctl stop unicorn
# sudo gitlab-ctl stop puma
# sudo gitlab-ctl stop sidekiq
# sudo systemctl stop gitlab-runsvdir
# sudo systemctl disable gitlab-runsvdir
# sudo rm /usr/lib/systemd/system/gitlab-runsvdir.service
# sudo systemctl daemon-reload
# sudo gitlab-ctl uninstall



# Check for previous versions
# sudo apt-cache madison gitlab-ce

# Remove current and install previous
# sudo apt remove gitlab-ce
# sudo apt install gitlab-ce=12.8.1-ce.0
# sudo gitlab-ctl reconfigure
# sudo gitlab-backup restore BACKUP=dump force=yes
# sudo gitlab-ctl start

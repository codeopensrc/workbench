#!/bin/bash

### Misc backup info

### Backup procedures
### https://docs.gitlab.com/omnibus/settings/backups.html

### Backup configs
# gitlab-ctl backup-etc && cd /etc/gitlab/config_backup && cp $(ls -t | head -n1) /secret/gitlab/backups/

OPT_VERSION=""

while getopts "a:b:v:ceg" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
        c) USE_CONSUL=true;;
        g) GC_DOCKER_REGISTRY=true;;
        v) OPT_VERSION=${OPTARG}_;;
        e) ENCRYPT=true;;
    esac
done


if [[ -z $S3_ALIAS ]]; then echo "Please provide s3 alias using -a S3_ALIAS"; exit ; fi
if [[ -z $S3_BUCKET_NAME ]]; then echo "Please provide s3 bucket name using -b S3_BUCKET_NAME"; exit ; fi


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

if [[ "$GC_DOCKER_REGISTRY" == true ]]; then
    # https://gitlab.com/help/administration/packages/container_registry.md#container-registry-garbage-collection
    sudo gitlab-ctl registry-garbage-collect -m

    # TODO: No Downtime with below link instructions(above cmd with -m flag ran for 1 second)
    # https://gitlab.com/help/administration/packages/container_registry.md#performing-garbage-collection-without-downtime
fi

## SSL Certs
mkdir -p $HOME/code/backups/letsencrypt
(cd /etc/ && tar -czvf $HOME/code/backups/letsencrypt/letsencrypt_$TODAY.tar.gz letsencrypt)
## SSH Keys
mkdir -p $HOME/code/backups/ssh_keys
(cd /etc/ssh/ && tar -czvf $HOME/code/backups/ssh_keys/ssh_keys_$TODAY.tar.gz ssh_host_*_key*)

gitlab-backup create BACKUP=dump GZIP_RSYNCABLE=yes
# CRON=1 suppresses output
# gitlab-backup create BACKUP=dump GZIP_RSYNCABLE=yes CRON=1

## Mattermost
mkdir -p $HOME/code/backups/mattermost
(cd /var/opt/gitlab/mattermost/ && tar -czvf $HOME/code/backups/mattermost/mattermost_data_$TODAY.tar.gz *)
sudo -i -u gitlab-psql -- /opt/gitlab/embedded/bin/pg_dump -h /var/opt/gitlab/postgresql mattermost_production | gzip > $HOME/code/backups/mattermost/mattermost_dbdump_$TODAY.sql.gz

##Grafana
mkdir -p $HOME/code/backups/grafana
(cd /var/opt/gitlab/grafana && tar -czvf $HOME/code/backups/grafana/grafana_data_$TODAY.tar.gz data)

GPG_EXT=""
if [[ -n $ENCRYPT ]]; then
    GPG_EXT=".gpg"
    bash $HOME/code/scripts/misc/encrypt.sh -f $HOME/code/backups/letsencrypt/letsencrypt_$TODAY.tar.gz
    bash $HOME/code/scripts/misc/encrypt.sh -f $HOME/code/backups/ssh_keys/ssh_keys_$TODAY.tar.gz
    bash $HOME/code/scripts/misc/encrypt.sh -f $HOME/code/backups/mattermost/mattermost_data_$TODAY.tar.gz
    bash $HOME/code/scripts/misc/encrypt.sh -f $HOME/code/backups/mattermost/mattermost_dbdump_$TODAY.sql.gz
    bash $HOME/code/scripts/misc/encrypt.sh -f $HOME/code/backups/grafana/grafana_data_$TODAY.tar.gz
    bash $HOME/code/scripts/misc/encrypt.sh -f /var/opt/gitlab/backups/dump_gitlab_backup.tar
    bash $HOME/code/scripts/misc/encrypt.sh -f /etc/gitlab/gitlab-secrets.json
fi

# Upload
/usr/local/bin/mc cp $HOME/code/backups/letsencrypt/letsencrypt_$TODAY.tar.gz${GPG_EXT} \
    $S3_ALIAS/$S3_BUCKET_NAME/admin_backups/letsencrypt_backups/$YEAR_MONTH/letsencrypt_$TODAY.tar.gz${GPG_EXT}

/usr/local/bin/mc cp $HOME/code/backups/ssh_keys/ssh_keys_$TODAY.tar.gz${GPG_EXT} \
    $S3_ALIAS/$S3_BUCKET_NAME/admin_backups/ssh_keys_backups/$YEAR_MONTH/ssh_keys_$TODAY.tar.gz${GPG_EXT}

/usr/local/bin/mc cp $HOME/code/backups/mattermost/mattermost_data_$TODAY.tar.gz${GPG_EXT} \
    $S3_ALIAS/$S3_BUCKET_NAME/admin_backups/mattermost_backups/$YEAR_MONTH/mattermost_data_$TODAY.tar.gz${GPG_EXT}

/usr/local/bin/mc cp $HOME/code/backups/mattermost/mattermost_dbdump_$TODAY.sql.gz${GPG_EXT} \
    $S3_ALIAS/$S3_BUCKET_NAME/admin_backups/mattermost_backups/$YEAR_MONTH/mattermost_dbdump_$TODAY.sql.gz${GPG_EXT}

/usr/local/bin/mc cp $HOME/code/backups/grafana/grafana_data_$TODAY.tar.gz${GPG_EXT} \
    $S3_ALIAS/$S3_BUCKET_NAME/admin_backups/grafana_backups/$YEAR_MONTH/grafana_data_$TODAY.tar.gz${GPG_EXT}

# The goal is to rsync over the previous days and keep snapshot once a week instead of storing a daily multi gig backup
/usr/local/bin/mc cp /var/opt/gitlab/backups/dump_gitlab_backup.tar${GPG_EXT} \
    $S3_ALIAS/$S3_BUCKET_NAME/admin_backups/gitlab_backups/$SUNDAY_YEAR_MONTH/dump_gitlab_backup_$SUNDAY.tar${GPG_EXT}

UPLOAD_EXIT_CODE=$?

# Dont keep secrets backup on server I guess? Directly upload the single json file
/usr/local/bin/mc cp /etc/gitlab/gitlab-secrets.json${GPG_EXT} \
    $S3_ALIAS/$S3_BUCKET_NAME/admin_backups/gitlab_backups/$SUNDAY_YEAR_MONTH/gitlab-secrets_$SUNDAY.json${GPG_EXT}

if [[ -n $OPT_VERSION ]]; then
    /usr/local/bin/mc cp /var/opt/gitlab/backups/dump_gitlab_backup.tar${GPG_EXT} \
        $S3_ALIAS/$S3_BUCKET_NAME/admin_backups/gitlab_backups/$SUNDAY_YEAR_MONTH/dump_gitlab_backup_${OPT_VERSION}$SUNDAY.tar${GPG_EXT}

    /usr/local/bin/mc cp /etc/gitlab/gitlab-secrets.json${GPG_EXT} \
        $S3_ALIAS/$S3_BUCKET_NAME/admin_backups/gitlab_backups/$SUNDAY_YEAR_MONTH/gitlab-secrets_${OPT_VERSION}$SUNDAY.json${GPG_EXT}
fi

if [[ -n $ENCRYPT ]]; then
    rm $HOME/code/backups/letsencrypt/letsencrypt_$TODAY.tar.gz
    rm $HOME/code/backups/ssh_keys/ssh_keys_$TODAY.tar.gz
    rm $HOME/code/backups/mattermost/mattermost_data_$TODAY.tar.gz
    rm $HOME/code/backups/mattermost/mattermost_dbdump_$TODAY.sql.gz
    rm $HOME/code/backups/grafana/grafana_data_$TODAY.tar.gz
    rm /var/opt/gitlab/backups/dump_gitlab_backup.tar
fi

# Cleanup every Sunday
if [[ "$TODAY" == "$SUNDAY" ]]; then
    rm -rf $HOME/code/backups/letsencrypt/*
    rm -rf $HOME/code/backups/ssh_keys/*
    rm -rf $HOME/code/backups/mattermost/*
    rm -rf $HOME/code/backups/grafana/*
fi


CHECK_ID=gitlab
SERVICE_ID="gitlab_backup"
TTL="72h5m"

### Register service and checks to display recent backups
if [[ $USE_CONSUL == true ]]; then
    bash $HOME/code/scripts/misc/update_backup_status.sh -c $CHECK_ID -s $SERVICE_ID -e $UPLOAD_EXIT_CODE -t $TTL
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

#!/bin/bash


##### NOTE: After a restore to a new machine, runners need to be re installed and connected
##### If cloning into a dev environment REMOVE repository mirroring
#####

OPT_VERSION=""

while getopts "a:b:v:f" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) S3_ALIAS=$OPTARG;;
        b) S3_BUCKET_NAME=$OPTARG;;
        f) FILE_NAME=$OPTARG;;
        v) OPT_VERSION=${OPTARG}_;;
    esac
done


if [[ -z $S3_ALIAS ]]; then echo "Please provide s3 alias using -a S3_ALIAS"; exit ; fi
if [[ -z $S3_BUCKET_NAME ]]; then echo "Please provide s3 bucket name using -b S3_BUCKET_NAME"; exit ; fi
# if [[ -z $FILE_NAME ]]; then echo "Please provide file name using -f FILE_NAME"; exit ; fi

# TODO: Implement a way to change the date in the string we're looking for befor we can have this more generalized
# if [[ -z $FILE_NAME ]]; then echo "Please provide FULL file location  using -f FILE_LOCATION"; exit ; fi


### SSL
for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/admin_backups/letsencrypt_backups/${YEAR_MONTH}/letsencrypt_${DATE}.tar.gz"
    LOCAL_FILE="$HOME/code/backups/letsencrypt/letsencrypt_$DATE.tar.gz"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then

        # Just downloading for now
        # letsencrypt
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        ### I dont think we do this unless its the same domain name
        # rm -rf /etc/letsencrypt/
        # tar -xzvf $LOCAL_FILE -C /etc/letsencrypt

        #### TODO: Restart services that rely on the keys in /etc/letsencrypt
        ####

        break
    fi
done


## SSH
for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/admin_backups/ssh_keys_backups/${YEAR_MONTH}/ssh_keys_${DATE}.tar.gz"
    LOCAL_FILE="$HOME/code/backups/ssh_keys/ssh_keys_$DATE.tar.gz"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then

        # ssh keys
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        TODAY=$(date +"%F")
        (cd /etc/ssh/ && tar -czvf /etc/ssh/ssh_keys_$TODAY.tar.gz ssh_host_*_key*)
        # Really is/should be done at bootup as well
        tar -xzvf $LOCAL_FILE -C /etc/ssh && chown root:root /etc/ssh/ssh_host_*_key*

        ### TODO: Restart sshd service, this will probably cause issues
        # service sshd restart

        break
    fi
done


## Gitlab
for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/admin_backups/gitlab_backups/${YEAR_MONTH}/dump_gitlab_backup_${OPT_VERSION}${DATE}.tar"
    LOCAL_FILE="/var/opt/gitlab/backups/dump_gitlab_backup_${DATE}.tar"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then

        # gitlabdump
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        # Gitlab must already be up and running
        # Backup path must be owned by git user
        sudo chown git.git $LOCAL_FILE

        # DB services must be stopped
        sudo gitlab-ctl stop unicorn
        sudo gitlab-ctl stop puma
        sudo gitlab-ctl stop sidekiq

        # Move current backup to .bak
        GITLAB_BACKUP_FILE="/var/opt/gitlab/backups/dump_gitlab_backup.tar"
        rm -rf $GITLAB_BACKUP_FILE.bak
        mv $GITLAB_BACKUP_FILE $GITLAB_BACKUP_FILE.bak

        # Move imported backup to previous backup's location
        mv $LOCAL_FILE $GITLAB_BACKUP_FILE

        # Restore using the imported backup's copy
        sudo gitlab-backup restore BACKUP=dump force=yes

        ### Probably shouldnt be done here until the secrets file back in place.
        ### As long as the correct secrets file is there we should be able to run this
        # sudo gitlab-ctl reconfigure
        # sudo gitlab-ctl restart
        # sudo gitlab-rake gitlab:check SANITIZE=true

        break
    fi
done


## Gitlab secrets
for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/admin_backups/gitlab_backups/${YEAR_MONTH}/gitlab-secrets_${OPT_VERSION}${DATE}.json"
    LOCAL_FILE="/etc/gitlab/gitlab-secrets_${DATE}.json"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then

        # gitlabsecrets
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        GITLAB_SECRETS_FILE="/etc/gitlab/gitlab-secrets.json"
        # Move current backup to .bak
        rm $GITLAB_SECRETS_FILE.bak
        mv $GITLAB_SECRETS_FILE $GITLAB_SECRETS_FILE.bak
        # Move imported backup to previous backup's location
        mv $LOCAL_FILE $GITLAB_SECRETS_FILE

        sudo gitlab-ctl reconfigure
        sudo gitlab-ctl restart
        sudo gitlab-rake gitlab:check SANITIZE=true

        break
    fi
done


## Mattermost
for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/admin_backups/mattermost_backups/${YEAR_MONTH}/mattermost_data_${DATE}.tar.gz"
    LOCAL_FILE="$HOME/code/backups/mattermost/mattermost_data_${DATE}.tar.gz"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then

        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        TODAY=$(date +"%F")
        MATTERMOST_DIR=/var/opt/gitlab/mattermost

        (cd $MATTERMOST_DIR/ && tar -czvf $MATTERMOST_DIR/mattermost_data_$TODAY.tar.gz *)
        tar -xzvf $LOCAL_FILE -C $MATTERMOST_DIR


        break
    fi
done

## Mattermost
for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/admin_backups/mattermost_backups/${YEAR_MONTH}/mattermost_dbdump_${DATE}.sql.gz"
    LOCAL_FILE="$HOME/code/backups/mattermost/mattermost_dbdump_${DATE}.sql.gz"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then

        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        ###! Going to give gitlab postgres db a second to restore
        echo "Wait 10"
        sleep 10;

        sudo gitlab-ctl stop mattermost
        sudo -i -u gitlab-psql -- /opt/gitlab/embedded/bin/dropdb -h /var/opt/gitlab/postgresql mattermost_production
        sudo -i -u gitlab-psql -- /opt/gitlab/embedded/bin/createdb -h /var/opt/gitlab/postgresql mattermost_production
        gunzip -c $LOCAL_FILE | sudo -i -u gitlab-psql -- /opt/gitlab/embedded/bin/psql -h /var/opt/gitlab/postgresql -d mattermost_production
        sudo gitlab-ctl start mattermost

        break
    fi
done


## Grafana
for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="${S3_ALIAS}/${S3_BUCKET_NAME}/admin_backups/grafana_backups/${YEAR_MONTH}/grafana_data_${DATE}.tar.gz"
    LOCAL_FILE="$HOME/code/backups/grafana/grafana_data_${DATE}.tar.gz"

    echo "Checking $REMOTE_FILE";
    /usr/local/bin/mc find $REMOTE_FILE > /dev/null;
    if [[ $? == 0 ]]; then

        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        /usr/local/bin/mc cp $REMOTE_FILE $LOCAL_FILE;

        TODAY=$(date +"%F")
        GRAFANA_DIR=/var/opt/gitlab/grafana

        (cd $GRAFANA_DIR/ && tar -czvf $GRAFANA_DIR/grafana_data_$TODAY.tar.gz data)
        tar -xzvf $LOCAL_FILE -C $GRAFANA_DIR
        chown -R gitlab-prometheus:gitlab-prometheus $GRAFANA_DIR/data
        sudo gitlab-ctl restart grafana

        break
    fi
done




# If some project/repo urls aren't working correctly
# Id say dont use unless you know what its doing
# sudo gitlab-rails runner "Project.where.not(import_url: nil).each { |p| p.import_data.destroy if p.import_data }"


# NOTE: Looks like its doing it already with "gitlab-backup restore" command
# Change ownership of registry
# https://docs.gitlab.com/ee/raketasks/backup_restore.html#container-registry-push-failures-after-restoring-from-a-backup
# sudo chown -R registry:registry /var/opt/gitlab/gitlab-rails/shared/registry/docker

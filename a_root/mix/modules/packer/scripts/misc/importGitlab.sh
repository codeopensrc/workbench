#!/bin/bash


##### NOTE: After a restore to a new machine, runners need to be re installed and connected
##### If cloning into a dev environment REMOVE repository mirroring
#####

while getopts "b:r:f" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BUCKET_NAME=$OPTARG;;
        f) FILE_NAME=$OPTARG;;
        r) REGION=$OPTARG;;
    esac
done


if [[ -z $BUCKET_NAME ]]; then echo "Please provide s3 bucket name using -b BUCKET"; exit ; fi
# if [[ -z $FILE_NAME ]]; then echo "Please provide file name using -f FILE_NAME"; exit ; fi
if [[ -z $REGION ]]; then echo "Please provide region using -r REGION"; exit ; fi

# TODO: Implement a way to change the date in the string we're looking for befor we can have this more generalized
# if [[ -z $FILE_NAME ]]; then echo "Please provide FULL file location  using -f FILE_LOCATION"; exit ; fi



for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="s3://${BUCKET_NAME}/admin_backups/letsencrypt_backups/${YEAR_MONTH}/letsencrypt_${DATE}.tar.gz"
    LOCAL_FILE="$HOME/code/backups/letsencrypt/letsencrypt_$DATE.tar.gz"

    echo "Checking $REMOTE_FILE";
    aws s3 ls $REMOTE_FILE --region $REGION;
    if [[ $? == 0 ]]; then

        # Just downloading for now
        # letsencrypt
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        aws s3 cp $REMOTE_FILE $LOCAL_FILE --region $REGION;

        ### I dont think we do this unless its the same domain name
        # rm -rf /etc/letsencrypt/
        # tar -xzvf $LOCAL_FILE -C /etc/letsencrypt

        #### TODO: Restart services that rely on the keys in /etc/letsencrypt
        ####

        break
    fi
done



for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="s3://${BUCKET_NAME}/admin_backups/ssh_keys_backups/${YEAR_MONTH}/ssh_keys_${DATE}.tar.gz"
    LOCAL_FILE="$HOME/code/backups/ssh_keys/ssh_keys_$DATE.tar.gz"

    echo "Checking $REMOTE_FILE";
    aws s3 ls $REMOTE_FILE --region $REGION;
    if [[ $? == 0 ]]; then

        # ssh keys
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        aws s3 cp $REMOTE_FILE $LOCAL_FILE --region $REGION;

        TODAY=$(date +"%F")
        (cd /etc/ssh/ && tar -czvf /etc/ssh/ssh_keys_$TODAY.tar.gz ssh_host_*_key*)
        # Really is/should be done at bootup as well
        tar -xzvf $LOCAL_FILE -C /etc/ssh && chown root:root /etc/ssh/ssh_host_*_key*

        ### TODO: Restart sshd service, this will probably cause issues
        # service sshd restart

        break
    fi
done



for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="s3://${BUCKET_NAME}/admin_backups/gitlab_backups/${YEAR_MONTH}/dump_gitlab_backup_${DATE}.tar"
    LOCAL_FILE="/var/opt/gitlab/backups/dump_gitlab_backup_${DATE}.tar"

    echo "Checking $REMOTE_FILE";
    aws s3 ls $REMOTE_FILE --region $REGION;
    if [[ $? == 0 ]]; then

        # gitlabdump
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        aws s3 cp $REMOTE_FILE $LOCAL_FILE --region $REGION;

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



for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="s3://${BUCKET_NAME}/admin_backups/gitlab_backups/${YEAR_MONTH}/gitlab-secrets_${DATE}.json"
    LOCAL_FILE="/etc/gitlab/gitlab-secrets_${DATE}.json"

    echo "Checking $REMOTE_FILE";
    aws s3 ls $REMOTE_FILE --region $REGION;
    if [[ $? == 0 ]]; then

        # gitlabsecrets
        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        aws s3 cp $REMOTE_FILE $LOCAL_FILE --region $REGION;

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



for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="s3://${BUCKET_NAME}/admin_backups/mattermost_backups/${YEAR_MONTH}/mattermost_data_${DATE}.tar.gz"
    LOCAL_FILE="$HOME/code/backups/mattermost/mattermost_data_${DATE}.tar.gz"

    echo "Checking $REMOTE_FILE";
    aws s3 ls $REMOTE_FILE --region $REGION;
    if [[ $? == 0 ]]; then

        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        aws s3 cp $REMOTE_FILE $LOCAL_FILE --region $REGION;

        TODAY=$(date +"%F")
        MATTERMOST_DIR=/var/opt/gitlab/mattermost

        (cd $MATTERMOST_DIR/ && tar -czvf $MATTERMOST_DIR/mattermost_data_$TODAY.tar.gz *)
        tar -xzvf $LOCAL_FILE -C $MATTERMOST_DIR


        break
    fi
done


for i in {0..15}; do
    DATE=$(date --date="$i days ago" +"%Y-%m-%d");
    YEAR_MONTH=$(date --date="$i days ago" +"%Y-%m")

    REMOTE_FILE="s3://${BUCKET_NAME}/admin_backups/mattermost_backups/${YEAR_MONTH}/mattermost_dbdump_${DATE}.sql.gz"
    LOCAL_FILE="$HOME/code/backups/mattermost/mattermost_dbdump_${DATE}.sql.gz"

    echo "Checking $REMOTE_FILE";
    aws s3 ls $REMOTE_FILE --region $REGION;
    if [[ $? == 0 ]]; then

        echo "Downloading $REMOTE_FILE to $LOCAL_FILE";
        aws s3 cp $REMOTE_FILE $LOCAL_FILE --region $REGION;

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






# If some project/repo urls aren't working correctly
# Id say dont use unless you know what its doing
# sudo gitlab-rails runner "Project.where.not(import_url: nil).each { |p| p.import_data.destroy if p.import_data }"


# NOTE: Looks like its doing it already with "gitlab-backup restore" command
# Change ownership of registry
# https://docs.gitlab.com/ee/raketasks/backup_restore.html#container-registry-push-failures-after-restoring-from-a-backup
# sudo chown -R registry:registry /var/opt/gitlab/gitlab-rails/shared/registry/docker

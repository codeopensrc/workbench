#!/bin/bash

MONGO_VERSION="4.4.6"
BIND_IPS="0.0.0.0"

while getopts "v:i:r:b" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        b) BACKUP=true;;
        i) BIND_IPS=$OPTARG;;
        r) REPLICA_SET_NAME=$OPTARG;;
        v) MONGO_VERSION=$OPTARG;;
    esac
done

MONGO_MAJOR_MINOR=${MONGO_VERSION%%.[0-9]}

# TODO: Detect proper version and IP input


### Backup and shutdown old for upgrade
if [ "$BACKUP" = true ]; then
    # backup all of mongo before
    # TODO: Check that mongo is up before attempting to dump
    bash /root/code/scripts/db/dumpmongo.sh

    # Chose one based on version
    # TODO: Auto detect which is supported
    # sudo service mongod stop
    sudo systemctl stop mongod
fi


sudo apt-get install -y gnupg;
wget -qO - https://www.mongodb.org/static/pgp/server-$MONGO_MAJOR_MINOR.asc | sudo apt-key add -


CODE_NAME=$(lsb_release -cs)
## Mongodb doesn't have a package/release for 22.04 jammy at this time
#https://askubuntu.com/questions/1402179/not-able-to-install-mongodb-in-ubuntu-22-04
#https://www.mongodb.com/community/forums/t/installing-mongodb-over-ubuntu-22-04/159931/83

## NOTE: This is insecure as its using an older vulnerable version libssl1
## All DB's in this repo will be going into containers soon, mainly for this type of scenario
## Use at your own risk
if [[ $CODE_NAME = "jammy" ]]; then 
    CODE_NAME=focal;
    #wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.16_amd64.deb
    #sudo apt-get update
    #dpkg -i libssl1.1_1.1.1f-1ubuntu2.16_amd64.deb
    #rm libssl1.1_1.1.1f-1ubuntu2.16_amd64.deb

    wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb
    sudo apt-get update
    dpkg -i libssl1.1_1.1.0g-2ubuntu4_amd64.deb
    rm libssl1.1_1.1.0g-2ubuntu4_amd64.deb
fi

echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $CODE_NAME/mongodb-org/$MONGO_MAJOR_MINOR multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-$MONGO_MAJOR_MINOR.list

sudo apt-get update

sudo apt install mongodb-org -y
## BIND_IPS can be a single address or comma deliminated set of ip/dns names

sed -i "s|bindIp: 0.0.0.0|bindIp: $BIND_IPS|" /etc/mongod.conf;
sed -i "s|bindIp: 127.0.0.1.*|bindIp: 127.0.0.1,$BIND_IPS|" /etc/mongod.conf;

if [[ -n $REPLICA_SET_NAME ]]; then
    sed -i "s|#replication:|replication:\n  replSetName: \"$REPLICA_SET_NAME\"|" /etc/mongod.conf;
fi


sudo systemctl daemon-reload;
sudo systemctl start mongod;
sudo systemctl enable mongod;

## To purge
#### sudo service mongod stop
#### sudo apt-get purge mongodb-org*
#### sudo rm -r /var/log/mongodb
#### sudo rm -r /var/lib/mongodb

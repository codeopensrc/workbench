#!/bin/bash

NODE_NAME=$(grep "127.0.1.1" /etc/hosts | cut -d " " -f3)
PRIVATE_IP=$(grep "vpc.my_private_ip" /etc/hosts | cut -d " " -f1)
BACKUP_FILE_LOCATION=$HOME/code/backups/etcd

if [[ -z $NODE_NAME ]]; then echo "Unable to retrieve NODE_NAME"; exit 1; fi
if [[ -z $PRIVATE_IP ]]; then echo "Unable to retrieve PRIVATE_IP"; exit 1; fi

mkdir -p $BACKUP_FILE_LOCATION
cp /var/lib/etcd/member/snap/db $BACKUP_FILE_LOCATION/db

if [[ ! -f "$BACKUP_FILE_LOCATION/db" ]]; then
    echo "Unable to find $BACKUP_FILE_LOCATION/db. exiting"
    exit 1
fi

rm -rf /var/lib/etcd
etcdutl snapshot restore $BACKUP_FILE_LOCATION/db \
    --name ${NODE_NAME} \
    --initial-cluster=${NODE_NAME}=https://${PRIVATE_IP}:2380 \
    --initial-advertise-peer-urls=https://${PRIVATE_IP}:2380 \
    --skip-hash-check=true \
    --data-dir=/var/lib/etcd

docker restart $(docker ps -a | grep -m 1 "kube-apiserver" | cut -d " " -f1)

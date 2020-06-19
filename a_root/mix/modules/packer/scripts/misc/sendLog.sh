#!/bin/bash

while getopts "i:l:s:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        i) DOCKER_IMAGE=$OPTARG;;
        l) LOGS_PREFIX=$OPTARG;;
        s) CONSUL_SERVICE=$OPTARG;;
    esac
done

TODAY=$(date +"%Y-%m-%d")

for CONTAINER in `docker ps -a -q -f "label=com.consul.service=$CONSUL_SERVICE"`; do
    /usr/bin/docker logs $CONTAINER -t >> $HOME/code/logs/"$LOGS_PREFIX"_"$TODAY".log
done

/usr/bin/docker run -v $HOME/code/logs:/logs $DOCKER_IMAGE \
    /logs/"$LOGS_PREFIX"_"$TODAY".log,/logs/errors.log

rm $HOME/code/logs/"$LOGS_PREFIX_$TODAY.log"
rm $HOME/code/logs/errors.log

#!/bin/bash

while getopts "f:r:s:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        f) FOLDER_LOCATION=$OPTARG;;
        r) REPO_NAME=$OPTARG;;
        s) DOCKER_SERVICE=$OPTARG;;
    esac
done

# NOTE: This is toggled off when being cloned in dev environments in terraform
RUN_SERVICE=true

if [[ "$RUN_SERVICE" != true ]]; then exit; fi

cd $FOLDER_LOCATION/$REPO_NAME
/usr/local/bin/docker-compose -f docker-compose.yml run -d $DOCKER_SERVICE

#!/bin/bash

#### NOTE: Currently this balance services relative to the amount of containers
####    on the docker host, but still attempts to spread and have at least one
####    container on each host.

# ID_TO_USE=5555
# SCALE_TO=8
# SERVICE_TO_REBAlANCE=sample_service

DELAY_BETWEEN_SERVICE_REBALANCE=0

while getopts "fas:n:i:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        f) FORCE=true;;
        a) REBALANCE_ALL=true;;
        i) ID_TO_USE=$OPTARG;;
        s) SERVICE_TO_REBAlANCE=$OPTARG;;
        n) SCALE_TO=$OPTARG;;
    esac
done

if [ -z $ID_TO_USE ]; then echo "Please provide an ID using the -i flag.    '-i FOUR_DIGIT_DOCKER_ID'"; exit; fi
if [ -z $SERVICE_TO_REBAlANCE ] && [ ! $REBALANCE_ALL ]; then echo "Please provide a Service to scale using the -s flag.  '-s SERVICE_NAME'"; exit; fi
if [ -z $SCALE_TO ] && [ ! $REBALANCE_ALL ]; then echo "Please provide desired number of services using the -n flag.   '-n NUM_SERVICES'"; exit; fi



if [[ $SCALE_TO > 8 ]] && [[ -z $FORCE ]]; then
    echo "Are you sure you wish to scale to $SCALE_TO?"
    echo "If so, please re-run with the -f flag"
    exit;
fi

DOCKER_NAME=$(docker-machine ls -t 3 --filter name=$ID_TO_USE -q)

if [ -z "$DOCKER_NAME" ]; then
    echo "Docker machine with id $ID_TO_USE not found.";
    exit;
fi


if [[ ! $REBALANCE_ALL ]]; then
    CURRENT_SCALE=`docker-machine ssh $DOCKER_NAME "docker service ls --filter name=$SERVICE_TO_REBAlANCE --format "{{.Replicas}}" | cut -d '/' -f1"`
    echo "Re-balancing and/or Scaling $SERVICE_TO_REBAlANCE: $CURRENT_SCALE to $SCALE_TO"
    docker-machine ssh $DOCKER_NAME "docker service update $SERVICE_TO_REBAlANCE --replicas=$SCALE_TO --force"
    echo "Sleeping $SCALE_WAIT_TIME seconds for graceful re-balance"
    sleep $DELAY_BETWEEN_SERVICE_REBALANCE
fi


if [[ $REBALANCE_ALL ]]; then
    for SERVICE_ID in `docker-machine ssh $DOCKER_NAME "docker service ls -q"`; do
        CURRENT_SERVICE=`docker-machine ssh $DOCKER_NAME "docker service ls --filter id=$SERVICE_ID --format "{{.Name}}""`;
        CURRENT_SCALE=`docker-machine ssh $DOCKER_NAME "docker service ls --filter id=$SERVICE_ID --format "{{.Replicas}}" | cut -d '/' -f1"`
        echo "Re-balancing and/or Scaling $CURRENT_SERVICE: $CURRENT_SCALE to $SCALE_TO"
        docker-machine ssh $DOCKER_NAME "docker service update $CURRENT_SERVICE --replicas=$SCALE_TO --force"
        echo "Sleeping $SCALE_WAIT_TIME seconds for graceful re-balance"
        sleep $DELAY_BETWEEN_SERVICE_REBALANCE
    done
fi



# if [[ $SCALE_TO < $CURRENT_SCALE ]]; then
#     echo "Please first scale down using ./scale_services.sh."
#     echo "Then re-run this script using a number equal to or greater than the current scale to force a graceful re-balance."
#     exit
# fi

# if [[ $REBALANCE_ALL ]]; then
#     for SERVICE_ID in `docker-machine ssh $DOCKER_NAME "docker service ls -q"`; do
#         CURRENT_SERVICE=`docker-machine ssh $DOCKER_NAME "docker service ls --filter id=$SERVICE_ID --format "{{.Name}}""`;
#         CURRENT_SCALE=`docker-machine ssh $DOCKER_NAME "docker service ls --filter id=$SERVICE_ID --format "{{.Replicas}}" | cut -d '/' -f1"`;
#         echo "Re-balancing $CURRENT_SERVICE: Current replica count is $CURRENT_SCALE";
#         docker-machine ssh $DOCKER_NAME "docker service update $SERVICE_ID --force;";
#         echo "Finished re-balancing $CURRENT_SERVICE";
#         echo "Sleeping $DELAY_BETWEEN_SERVICE_REBALANCE seconds for graceful re-balance";
#         sleep $DELAY_BETWEEN_SERVICE_REBALANCE;
#     done
# fi

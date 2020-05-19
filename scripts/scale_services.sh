#!/bin/bash

# ID_TO_USE=5555
# SCALE_TO=8
# SERVICE_TO_SCALE=sample_service

### When we used a delay between each update
# SCALE_WAIT_TIME=10

# shift; shift;
while getopts "afs:n:i:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        f) FORCE=true;;
        i) ID_TO_USE=$OPTARG;;
        s) SERVICE_TO_SCALE=$OPTARG;;
        n) SCALE_TO=$OPTARG;;
        a) SCALE_ALL=true;;
    esac
done

if [ -z $ID_TO_USE ]; then echo "Please provide an ID using the -i flag.    '-i FOUR_DIGIT_DOCKER_ID'"; exit; fi
if [ -z $SERVICE_TO_SCALE ] && [ $SCALE_ALL != "true" ]; then echo "Please provide a Service to scale using the -s flag.  '-s SERVICE_NAME'"; exit; fi
if [ -z $SCALE_TO ]; then echo "Please provide desired number of services using the -n flag.   '-n NUM_SERVICES'"; exit; fi

if [[ $SCALE_TO > 8 ]] && [[ -z $FORCE ]]; then
    echo "Are you should you wish to scale to $SCALE_TO?"
    echo "If so, please re-run with the -f flag"
    exit;
fi

DOCKER_NAME=$(docker-machine ls -t 3 --filter name=$ID_TO_USE -q)

if [ -z "$DOCKER_NAME" ]; then
    echo "Docker machine with id $ID_TO_USE not found.";
    exit;
fi

if [[ $SCALE_ALL ]]; then
    for SERVICE_ID in `docker-machine ssh $DOCKER_NAME "docker service ls -q"`; do
        CURRENT_SERVICE=`docker-machine ssh $DOCKER_NAME "docker service ls --filter id=$SERVICE_ID --format "{{.Name}}""`;
        CURRENT_SCALE=`docker-machine ssh $DOCKER_NAME "docker service ls --filter id=$SERVICE_ID --format "{{.Replicas}}" | cut -d '/' -f1"`
        echo "Scaling $CURRENT_SERVICE: $CURRENT_SCALE to $SCALE_TO"
        docker-machine ssh $DOCKER_NAME "docker service scale $CURRENT_SERVICE=$SCALE_TO"
    done
else
    CURRENT_SCALE=`docker-machine ssh $DOCKER_NAME "docker service ls --filter name=$SERVICE_TO_SCALE --format "{{.Replicas}}" | cut -d '/' -f1"`
    echo "Scaling $SERVICE_TO_SCALE: $CURRENT_SCALE to $SCALE_TO"
    docker-machine ssh $DOCKER_NAME "docker service scale $SERVICE_TO_SCALE=$SCALE_TO"
fi



### We used the below when we worried about scaling down. We would scale down one service at a time
### Docker fixed an internal load balancing bug in 18.02 that was preventing zero downtime
###  deployments/maintenence unless you heavy-handly changed DNS to a different swarm

# echo "CUR: $CURRENT_SCALE"

# if [[ $CURRENT_SCALE > $SCALE_TO ]]; then
#     for ((i=$CURRENT_SCALE-1,k=i+1;i>=$SCALE_TO;--i, k--)); do
#         echo "Scaling $SERVICE_TO_SCALE: $k to $i   Goal: $SCALE_TO"
#         docker-machine ssh $DOCKER_NAME "docker service scale $SERVICE_TO_SCALE=$i"
#         if [[ $i > $SCALE_TO ]]; then
#             echo "Scaling $SERVICE_TO_SCALE: $((--k)) to $((--i)) in $SCALE_WAIT_TIME seconds    Goal: $SCALE_TO"
#             ((++k))
#             ((++i))
#         fi
#         echo "Sleeping $SCALE_WAIT_TIME seconds for graceful scale down"
#         sleep $SCALE_WAIT_TIME
#     done
# fi
#
# if [[ $CURRENT_SCALE < $SCALE_TO ]]; then
#     echo "Scaling $SERVICE_TO_SCALE: $CURRENT_SCALE to $SCALE_TO"
#     docker-machine ssh $DOCKER_NAME "docker service scale $SERVICE_TO_SCALE=$SCALE_TO"
#     echo "Sleeping $SCALE_WAIT_TIME seconds for graceful scale up"
#     sleep $SCALE_WAIT_TIME
# fi

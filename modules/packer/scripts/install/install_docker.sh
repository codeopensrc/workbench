#!/bin/sh
set -e

### TODO: Multi-arch support using `docker buildx build` and `docker buildx bake -f docker-compose.yml`
## https://docs.docker.com/buildx/working-with-buildx/
## https://medium.com/@artur.klauser/building-multi-architecture-docker-images-with-buildx-27d80f7e2408#589b
##  docker buildx support needs
## `sudo apt-get install -y qemu-user-static`

DOCKER_VER=""
DEFAULT_DOCKER_VER="19.03.12"

while getopts "v:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        v) DOCKER_VER=$OPTARG;;
    esac
done


if [ -z $DOCKER_VER ] || [ $DOCKER_VER = "" ] || [ $DOCKER_VER = %%%REPLACE_ME%%% ]; then
    DOCKER_VER=$DEFAULT_DOCKER_VER
fi

FORMATTED_VER="5:${DOCKER_VER}~3-0~ubuntu-`lsb_release -cs`"
# 5:19.03.12~3-0~ubuntu-xenial

# apt-get remove docker docker-engine docker.io containerd runc

apt-get update

apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common -y

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

# Add 'edge' for even new releases

apt-get update

# Going to use for debugging why a particular version not available/installed
apt-cache madison docker-ce


# Trying to ramp up our vm provisioning/releases and keep up with gitlab and docker version releases
# Any point they are a major version behind we should be intentionally upgrading
# Otherwise it is VERY easy to fall behind and need to skip multiple releases which is no bueno
# TODO: Due to "docker-machine create" hanging with get.docker.com as engine install url if docker install
#  done previously and get.docker.com updates/uses a new version, we will need to be pinning docker versions for
#  reliable and stable deployments due to potential mismatches (machine hang adds 30% deployment time minimum)

# This will be more seamless when changing the version of an installed software package procs creating a new image
apt-get install docker-ce=$FORMATTED_VER docker-ce-cli=$FORMATTED_VER containerd.io -y


# Enable docker on boot
sudo systemctl enable docker

#systemctl daemon reload
#sleep 10
#systemctl restart docker
#sleep 20

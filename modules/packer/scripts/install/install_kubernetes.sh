#!/bin/bash

VERSION="1.22.1-00"
HELM_VERSION="3.8.2-1"

while getopts "v:h:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        v) VERSION=$OPTARG;;
        h) HELM_VERSION=$OPTARG;;
    esac
done

if [[ ! -f $HOME/.local/bin/kubectl ]] && [[ ! -f /usr/local/bin/kubectl ]] && [[ ! -f /usr/bin/kubectl ]]; then
    # Install kubeadm, kubelet, kubeadm
    # Download gpg
    sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
    # Add apt
    ### TODO: detect os release for deb
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    # Install
    sudo apt-get update;
    ## dpkg can stay briefly locked after update..
    sleep 20;
    if [[ ${VERSION} = "latest" ]]; then
        sudo apt-get install -y kubelet kubeadm kubectl
    else
        sudo apt-get install -y kubelet=${VERSION} kubeadm=${VERSION} kubectl=${VERSION}
    fi

    # apt list -a kubeadm | head -5

    # Im assuming this prevents it from upgrading
    sudo apt-mark hold kubelet kubeadm kubectl
fi

##! Installs helm - deployment tool for kubernetes
##! https://docs.helm.sh/docs/intro/install/
if [[ ! -f $HOME/.local/bin/helm ]] && [[ ! -f /usr/local/bin/helm ]] && [[ ! -f /usr/bin/helm ]]; then
    curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
    sudo apt-get install apt-transport-https --yes
    echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update
    sudo apt-get install -y helm=${HELM_VERSION}
fi

## This is to be run during packer init so disable kubelet service
systemctl stop kubelet

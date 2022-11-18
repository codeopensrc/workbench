#!/bin/bash

VERSION="1.24.7-00"
HELM_VERSION="3.8.2-1"
SKAFFOLD_VERSION="2.0.0"

while getopts "v:h:s:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        v) VERSION=$OPTARG;;
        h) HELM_VERSION=$OPTARG;;
        s) SKAFFOLD_VERSION=$OPTARG;;
    esac
done

if [[ ! -f $HOME/.local/bin/kubectl ]] && [[ ! -f /usr/local/bin/kubectl ]] && [[ ! -f /usr/bin/kubectl ]]; then
    # Install kubeadm, kubelet, kubeadm
    # Download gpg
    sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
    # Add apt
    ### TODO: detect os release for deb
    ### Package manager maintainers sometimes dont port over to the latest release right away so keys/packages still
    ###  point to an older releases repository. In this case we're still using 'xenial' even on the 'jammy' ubuntu release
    ## https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
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

    # Prevents it from upgrading
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

##! Installs skaffold - deployment tool for kubernetes
##! https://skaffold.dev/docs/install
if [[ ! -f $HOME/.local/bin/skaffold ]] && [[ ! -f /usr/local/bin/skaffold ]] && [[ ! -f /usr/bin/skaffold ]]; then
    curl -L https://storage.googleapis.com/skaffold/releases/v${SKAFFOLD_VERSION}/skaffold-linux-amd64 -o /tmp/skaffold-linux
    install /tmp/skaffold-linux /usr/local/bin/skaffold
    rm -rf /tmp/skaffold-linux
fi

## This is to be run during packer init so disable kubelet service
systemctl stop kubelet

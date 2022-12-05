#!/bin/bash

PATH=$PATH:/usr/bin

### Until its integrated and stable in our images, install/detect here
VERSION="1.24.7-00"
HELM_VERSION="3.8.2-1"
SKAFFOLD_VERSION="2.0.0"

while getopts "i:t:h:j:k:v:c:s:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        i) API_VPC_IP=$OPTARG;;
        j) JOIN_COMMAND=$OPTARG;;
        k) CERTIFICATE_KEY=$OPTARG;;
        t) TOKEN=$OPTARG;;
        c) CERT_HASH=$OPTARG;;
        v) VERSION=$OPTARG;;
        h) HELM_VERSION=$OPTARG;;
        s) SKAFFOLD_VERSION=$OPTARG;;
    esac
done

## TODO: Detect currently installed kubectl and install/upgrade if our provided version different

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

## Moving to installation and stopping kubelet in packer, so ensure its enabled here
systemctl start kubelet


if [[ -z $JOIN_COMMAND ]]; then
    echo "No join specified, trying consul"
    JOIN_COMMAND=$(consul kv get kube/joincmd)
    if [[ -z $JOIN_COMMAND ]]; then
        if [[ -z $API_VPC_IP ]]; then echo "Missing API_VPC_IP. Use -i"; exit; fi
        if [[ -z $TOKEN ]]; then echo "Missing TOKEN. Use -t"; exit; fi
        if [[ -z $CERT_HASH ]]; then echo "Missing CERT_HASH. Use -c"; exit; fi
    fi
fi
## Ive run on each node so far, not sure if we just need on controlplane
## iptables see bridged traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system


## Ive run on each node so far, not sure if we just need on controlplane
## configure cgroup driver
### TODO: Docs no longer show these being needed/used
### So far worked without it

#sudo mkdir -p /etc/docker
#cat <<EOF | sudo tee /etc/docker/daemon.json
#{
#  "exec-opts": ["native.cgroupdriver=systemd"],
#  "log-driver": "json-file",
#  "log-opts": {
#    "max-size": "100m"
#  },
#  "storage-driver": "overlay2"
#}
#EOF
#sudo systemctl enable docker
#sudo systemctl daemon-reload
#sudo systemctl restart docker


mkdir -p $HOME/.kube

## The cgroup driver is systemd by default in 1.22+ kubernetes versions
#https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/configure-cgroup-driver/#configuring-the-kubelet-cgroup-driver

### Kubernetes 1.24+ deprecated the dockershim integrated in kubernetes for the container runtime
### The following steps install an adapter to continue using the Docker Engine that is CRI compliant
### This has to be done on each node
### TODO: Now that we have to install go.. adapt this to install specific go versions

DIR_BEFORE_INSTALL=$PWD
### Start
###Install GO###
curl -Lo go1.19.3.linux-amd64.tar.gz https://go.dev/dl/go1.19.3.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.19.3.linux-amd64.tar.gz
rm go1.19.3.linux-amd64.tar.gz
source ~/.bash_profile

git clone https://github.com/Mirantis/cri-dockerd.git /etc/cri-dockerd
cd /etc/cri-dockerd
mkdir bin
go build -o bin/cri-dockerd
install -o root -g root -m 0755 bin/cri-dockerd /usr/local/bin/cri-dockerd
cp -a packaging/systemd/* /etc/systemd/system
sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
cat /etc/systemd/system/cri-docker.service
systemctl daemon-reload
systemctl enable cri-docker.service
systemctl enable --now cri-docker.socket
### End

cd $DIR_BEFORE_INSTALL

## On worker node
WORKER_VPC_IP=$(grep "vpc.my_private_ip" /etc/hosts | cut -d " " -f1)
#https://kubernetes.io/docs/tasks/tls/certificate-rotation/  ## Not sure if we need --rotate-certificates on non-master
FEATURE_GATES="--feature-gates=StatefulSetAutoDeletePVC=true"
echo "KUBELET_EXTRA_ARGS=\"--node-ip=$WORKER_VPC_IP $FEATURE_GATES\"" > /etc/default/kubelet
## Replace  {API_VPC_IP}   {TOKEN}   and   {CERT_HASH}
if [[ -n $JOIN_COMMAND ]]; then
    echo "Trying joincmd: $JOIN_COMMAND"
    if [[ -n $CERTIFICATE_KEY ]]; then
        $JOIN_COMMAND --control-plane --apiserver-advertise-address $WORKER_VPC_IP --certificate-key $CERTIFICATE_KEY
    else
        $JOIN_COMMAND
    fi
else
    if [[ -n $CERTIFICATE_KEY ]]; then
        kubeadm join ${API_VPC_IP}:6443 --token ${TOKEN} --discovery-token-ca-cert-hash ${CERT_HASH} --control-plane \
            --apiserver-advertise-address $WORKER_VPC_IP --certificate-key $CERTIFICATE_KEY
    else
        kubeadm join ${API_VPC_IP}:6443 --token ${TOKEN} --discovery-token-ca-cert-hash ${CERT_HASH}
    fi
fi

if [[ -n $CERTIFICATE_KEY ]]; then
    sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
else
    sudo cp /etc/kubernetes/kubelet.conf $HOME/.kube/config
fi
sudo chown $(id -u):$(id -g) $HOME/.kube/config

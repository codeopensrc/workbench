#!/bin/bash

### Until its integrated and stable in our images, install/detect here
VERSION="1.22.1-00"

## TODO: Predict interface, eth1 if available otherwise eth0 
NET_IFACE=eth1

while getopts "i:v:gr" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        i) NET_IFACE=$OPTARG;;
        v) VERSION=$OPTARG;;
        g) GET_JOIN="true";;
        r) RESET="true";;
    esac
done

function getclusterjoin() {
    ## Need 3 backslashes to escape a backslash here
    CMD=$(tr -d "\r\n\t\\\\" < $HOME/.kube/joininfo.txt)
    echo "$CMD"
    consul kv put kube/joincmd "$CMD"
}

if [[ -n $GET_JOIN ]]; then getclusterjoin; exit; fi

if [[ ! -f $HOME/.local/bin/kubectl ]] && [[ ! -f /usr/local/bin/kubectl ]] && [[ ! -f /usr/bin/kubectl ]]; then
    # Install kubeadm, kubelet, kubeadm
    # Download gpg
    sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
    # Add apt
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    # Install
    sudo apt-get update && sudo apt-get install -y kubelet=${VERSION} kubeadm=${VERSION} kubectl=${VERSION}
    # apt list -a kubeadm | head -5

    # Im assuming this prevents it from upgrading
    sudo apt-mark hold kubelet kubeadm kubectl
fi



### Reset cluster
### ATM these are instuctions and not runnable via arg
######################################################
#TODO: Copy paste instructions to remove each each node waiting for input to proceed
if [[ $RESET = "true" ]]; then
    echo "Review script for attempting to reset";
    exit


    ######## For removing a worker from the cluster ########

    #### TODO: Get all nodes and loop
    #### On controlplane
    # kubectl drain <node name> --delete-emptydir-data --force --ignore-daemonsets

    #### On worker 
    # kubeadm reset
        #### Instructions on worker after reset
        ####  "The reset process does not clean CNI configuration. To do so, you must remove /etc/cni/net.d"
        # rm -rf /etc/cni/net.d
        ####  "The reset process does not clean your kubeconfig files and you must remove them manually."
        ####  "Please, check the contents of the $HOME/.kube/config file"
        # rm $HOME/.kube/config


    #### Assuming controlplane
    # iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

    #### Control plane
    # kubectl delete node <node name>

    ############################################################
    ###### For reseting the cluster after removing workers ########

    # kubeadm reset
        #### Instructions on worker after reset
        ####  "The reset process does not clean CNI configuration. To do so, you must remove /etc/cni/net.d"
        # rm -rf /etc/cni/net.d
        ####  "The reset process does not clean your kubeconfig files and you must remove them manually."
        ####  "Please, check the contents of the $HOME/.kube/config file"
        # rm $HOME/.kube/config

    # iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

    #########################################################
fi
######################################################


## Ive run on each node so far, not sure if we just need on controlplane
## iptables see bridged traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system


## Ive run on each node so far, not sure if we just need on controlplane
## configure cgroup driver
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
sudo systemctl enable docker
sudo systemctl daemon-reload
sudo systemctl restart docker


## Get images
kubeadm config images pull


mkdir -p $HOME/.kube

## Init cluster
API_VPC_IP=$(grep "vpc.my_private_ip" /etc/hosts | cut -d " " -f1)
echo "KUBELET_EXTRA_ARGS=\"--node-ip=$API_VPC_IP\"" > /etc/default/kubelet
kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$API_VPC_IP | grep -A 1 "kubeadm join" | tee $HOME/.kube/joininfo.txt
## TODO: Format join command to be easily read in from file as a command


### On control-plane copy config file to local dir so we can run commands
# NOTE: Do not copy this file anywhere else, key to cluster
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


#### Install a Pod Network CNI addon - Here we're using flannel
#### We're only allowing our vpc into 8472
## We curl it, sed to add our iface, apply and write to curl-kube-flannel.yml for debuggings sake
curl https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml \
  | sed "s/\([[:space:]]*\)- --kube-subnet-mgr/\1- --kube-subnet-mgr\n\1- --iface=$NET_IFACE/" \
  | tee $HOME/.kube/curl-kube-flannel.yml \
  | kubectl apply -f -

## Let policies apply
echo "Waiting 30 for CNI addon"
sleep 30

## To verify 
## ps -ax | grep iface


echo "===================================="
echo "Command to join workers to this cluster:"

getclusterjoin

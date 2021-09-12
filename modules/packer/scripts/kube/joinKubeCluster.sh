#!/bin/bash

### Until its integrated and stable in our images, install/detect here
VERSION="1.22.1-00"

while getopts "i:t:h:j:v:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        i) API_VPC_IP=$OPTARG;;
        j) JOIN_COMMAND=$OPTARG;;
        t) TOKEN=$OPTARG;;
        h) HASH=$OPTARG;;
        v) VERSION=$OPTARG;;
    esac
done


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


if [[ -z $JOIN_COMMAND ]]; then
    echo "No join specified, trying consul"
    JOIN_COMMAND=$(consul kv get kube/joincmd)
    if [[ -z $JOIN_COMMAND ]]; then
        if [[ -z $API_VPC_IP ]]; then echo "Missing API_VPC_IP. Use -i"; exit; fi
        if [[ -z $TOKEN ]]; then echo "Missing TOKEN. Use -t"; exit; fi
        if [[ -z $HASH ]]; then echo "Missing HASH. Use -h"; exit; fi
    fi
fi
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


## On worker node
WORKER_VPC_IP=$(grep "vpc.my_private_ip" /etc/hosts | cut -d " " -f1)
echo "KUBELET_EXTRA_ARGS=\"--node-ip=$WORKER_VPC_IP\"" > /etc/default/kubelet
## Replace  {API_VPC_IP}   {TOKEN}   and   {HASH}
if [[ -n $JOIN_COMMAND ]]; then
    echo "Trying joincmd: $JOIN_COMMAND"
    $JOIN_COMMAND
else
    kubeadm join ${API_VPC_IP}:6443 --token ${TOKEN} --discovery-token-ca-cert-hash ${HASH}
fi

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/kubelet.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

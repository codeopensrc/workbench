#!/bin/bash

## According to https://kubernetes.io/docs/tasks/tls/certificate-rotation/#enabling-client-certificate-rotation
##  we can add `--rotate-certificates` to the kubelet command and  it should work
## We added it to our /etc/default/kublet file as an extra arg before running `kubeadm init` command, which should propagate
##  to all the other nodes as well. If certificates dont auto rotate (1 hear exp by default) then we should add it to the join command as well

## https://stackoverflow.com/questions/49885636/kubernetes-expired-certificate

### If the certs didnt auto renew that means youre here and need to renew them manually

## Optionally backup certs
#root@kube-master-1:~# cp -R /etc/kubernetes/ssl /etc/kubernetes/ssl.backup
#root@kube-master-1:~# cp /etc/kubernetes/admin.conf /etc/kubernetes/admin.conf.backup
#root@kube-master-1:~# cp /etc/kubernetes/controller-manager.conf /etc/kubernetes/controller-manager.conf.backup
#root@kube-master-1:~# cp /etc/kubernetes/kubelet.conf /etc/kubernetes/kubelet.conf.backup
#root@kube-master-1:~# cp /etc/kubernetes/scheduler.conf /etc/kubernetes/scheduler.conf.backup

kubeadm certs renew all

## Regular output from above indicates to restart the following services -
## "Done renewing certificates. You must restart the kube-apiserver, kube-controller-manager, kube-scheduler and etcd, so that they can use the new certificates."

#You may have to restart the kube-apiserver on all masters nodes.

echo "Sleep 10 cause why not"
sleep 10

## If you managed to catch renewing the certs before their renewed and still have kubectl access might be able to kill pods

## Idk if this works but worth a shot
kubectl get pods > /dev/null
EXIT_CODE=$?
if [[ $EXIT_CODE = "0" ]]; then
    kubectl -n kube-system delete pod -l 'component=kube-apiserver'
    kubectl -n kube-system delete pod -l 'component=kube-controller-manager'
    kubectl -n kube-system delete pod -l 'component=kube-scheduler'
    kubectl -n kube-system delete pod -l 'component=etcd'
else 
    API_SERVER_CONTAINER=$(docker ps | grep k8s_kube-apiserver | cut -f1 -d " ")
    CONTROLLER_CONTAINER=$(docker ps | grep k8s_kube-controller-manager | cut -f1 -d " ")
    SCHEDULER_CONTAINER=$(docker ps | grep k8s_kube-scheduler | cut -f1 -d " ")
    ETCD_CONTAINER=$(docker ps | grep k8s_etcd | cut -f1 -d " ")
    docker kill $API_SERVER_CONTAINER
    docker kill $CONTROLLER_CONTAINER
    docker kill $SCHEDULER_CONTAINER
    docker kill $ETCD_CONTAINER
fi

echo "Sleep 15 to wait for containers"
sleep 15

echo "Moving current config at /root/.kube/config to /root/.kube/old-config"
mv /root/.kube/config /root/.kube/old-config

echo "Moving new config to /root/.kube/config"
cp /etc/kubernetes/admin.conf /root/.kube/config

echo "Running 'kubectl get nodes' to test new config"
kubectl get nodes

echo "Config is working if above command worked successfully"

echo "And lastly outputing cert expiration for review"
kubeadm certs check-expiration

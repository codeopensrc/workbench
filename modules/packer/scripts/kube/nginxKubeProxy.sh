#!/bin/bash

ROOT_DOMAIN=$(consul kv get domainname)
CONSUL_KV_APPS="applist/"
PROD_NS="production"
BETA_NS="beta"
DEV_NS="dev"
OPT_VERSION="stable"

## TLDR: Use main nginx docker over alpine -
##  Alpine has issues with DNS in k8s, namely the resolver that works in vanilla nginx
##  Something that worked but very inconsistent, couldnt get to work more than 50%ish
##   even doing doing it before running the entrypoint
##  https://github.com/gliderlabs/docker-alpine/issues/539#issuecomment-856066068

while getopts "a:b:d:p:r:v:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) CONSUL_KV_APPS=${OPTARG};;
        b) BETA_NS=${OPTARG};;
        d) DEV_NS=${OPTARG};;
        p) PROD_NS=${OPTARG};;
        r) ROOT_DOMAIN=${OPTARG};;
        v) OPT_VERSION=${OPTARG};;
    esac
done

if [[ -z $ROOT_DOMAIN ]]; then echo "Domain empty. Use -r to provide root_domain (not fqdn)."; exit; fi


## Why we need it -
## https://stackoverflow.com/questions/43326913/nginx-proxy-pass-directive-string-interpolation/43341304#43341304
RESOLVER="kube-dns.kube-system.svc.cluster.local"
SERVICE_BASE_DNS="svc.cluster.local"

IMAGE=nginx
TAG=${OPT_VERSION}
IMAGE_PORT=80
APPNAME=nginx-proxy
NODEPORT=31000


echo "APPNAME: $APPNAME"
echo "IMAGE: $IMAGE"
echo "TAG: $TAG"
echo "IMAGE_PORT: $IMAGE_PORT"
echo "ROOT_DOMAIN: $ROOT_DOMAIN"
#exit

## Our keys are CONSUl_KV_APPS/servicename => subdomain
KEYS=$(consul kv get -recurse $CONSUL_KV_APPS | sed "s|$CONSUL_KV_APPS||")
SRV=($(echo "$KEYS" | cut -d ":" -f1))
DNS=($(echo "$KEYS" | cut -d ":" -f2-))


#exit

## $http_host is host:port
## $host is just host
NGINX_FILE='
resolver '${RESOLVER}' valid=5s;
\n
map \$host \$x {
    \n hostnames;
    \n '$(for i in "${!DNS[@]}"; do \
        echo "${DNS[$i]}.${ROOT_DOMAIN} ${SRV[$i]}.${PROD_NS}.${SERVICE_BASE_DNS};\n"; \
        echo "${DNS[$i]}.${BETA_NS}.${ROOT_DOMAIN} ${SRV[$i]}.${BETA_NS}.${SERVICE_BASE_DNS};\n"; \
        echo "${DNS[$i]}.${DEV_NS}.${ROOT_DOMAIN} ${SRV[$i]}.${DEV_NS}.${SERVICE_BASE_DNS};\n"; \
        echo "\\\"~^(?<ref>[-\\w]+)\\.(?<ns>[-\\w]+)\\.${DNS[$i]}\\.${DEV_NS}\\.${ROOT_DOMAIN}\\\" \\\$ref-${SRV[$i]}.\\\$ns.${SERVICE_BASE_DNS};\n\n"; \
    done)'
}
\n
server {
    listen *:80;
    server_name *.'${ROOT_DOMAIN}';
    location / {
        proxy_pass "http://\$x";
    }
}\n'

## Create a kubernetes service
## Create a kubernetes deployment
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $APPNAME
spec:
  type: NodePort
  selector:
    app: $APPNAME
  ports:
    - protocol: TCP
      port: 80
      targetPort: $IMAGE_PORT
      nodePort: $NODEPORT
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APPNAME
  labels:
    app: $APPNAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APPNAME
  template:
    metadata:
      labels:
        app: $APPNAME
    spec:
      containers:
      - name: $APPNAME
        image: $IMAGE:$TAG
        ports:
        - containerPort: $IMAGE_PORT
        volumeMounts:
        - mountPath: /etc/nginx/templates
          name: conf-volume
      initContainers:
      - name: ${APPNAME}-init
        image: $IMAGE:$TAG
        command: ['sh', '-c', 'printf "$NGINX_FILE" | tee /etc/nginx/templates/services.conf.template'] 
        volumeMounts:
        - mountPath: /etc/nginx/templates
          name: conf-volume
      volumes:
      - name: conf-volume
        emptyDir:
          medium: Memory
          sizeLimit: "3M"
EOF


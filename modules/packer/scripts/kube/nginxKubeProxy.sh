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

while getopts "a:b:d:p:r:v:n:i:c:s" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) CONSUL_KV_APPS=${OPTARG};;
        b) BETA_NS=${OPTARG};;
        d) DEV_NS=${OPTARG};;
        p) PROD_NS=${OPTARG};;
        r) ROOT_DOMAIN=${OPTARG};;
        v) OPT_VERSION=${OPTARG};;
        n) OPT_NODEPORT=${OPTARG};;
        i) EXTERNAL_IPS=${OPTARG};;
        c) SSL_CERTS=${OPTARG};;
        s) SSL=true;;
    esac
done

if [[ -z $ROOT_DOMAIN ]]; then echo "Domain empty. Use -r to provide root_domain (not fqdn)."; exit; fi

echo "Starting the nginxKubeProxy service"
echo "Make sure any apps you wish to be routed are in consuls KV store"
echo "applist/SERVICE => SUBDOMAIN   (not the fqdn) -> 'app' .domain.com"

## Why we need it -
## https://stackoverflow.com/questions/43326913/nginx-proxy-pass-directive-string-interpolation/43341304#43341304
RESOLVER="kube-dns.kube-system.svc.cluster.local"
SERVICE_BASE_DNS="svc.cluster.local"

IMAGE=nginx
TAG=${OPT_VERSION}
HTTP_PORT=80
HTTPS_PORT=443
APPNAME=nginx-proxy
NODEPORT=31000
CERTPORT=7080

if [[ -n $OPT_NODEPORT ]]; then NODEPORT=$OPT_NODEPORT; fi

echo "APPNAME: $APPNAME"
echo "IMAGE: $IMAGE"
echo "TAG: $TAG"
echo "NODEPORT: $NODEPORT"
echo "ROOT_DOMAIN: $ROOT_DOMAIN"
#exit

## Our keys are CONSUl_KV_APPS/servicename => subdomain
## TODO: If any key doesnt have a value the whole thing breaks down with arrays not synced
KEYS=$(consul kv get -recurse $CONSUL_KV_APPS | sed "s|$CONSUL_KV_APPS||")
SRV=($(echo "$KEYS" | cut -d ":" -f1))
DNS=($(echo "$KEYS" | cut -d ":" -f2-))



if [[ -z $SSL ]]; then
    COMMENT_IF_NO_SSL="#"
    SERVICE_NODEPORT="nodePort: $NODEPORT"
else
    COMMENT_IF_SSL="#"
    SERVICE_NODEPORT=""
    SSL_SERVICE=$(cat <<-EOF | sed -r "s/  (.+)/      \1/g"
	- name: https
	  protocol: TCP
	  port: $HTTPS_PORT
	  targetPort: 443
	EOF
	)

    if [[ -z $EXTERNAL_IPS ]]; then
        echo "Using -s for SSL requires external IPs using the -i flag. -i IP1,IP2 etc. Exiting"
        exit
    fi

    SPLIT_IPS=( $(echo "$EXTERNAL_IPS" | tr "," "\n") )
    IPS=$(for IP in "${SPLIT_IPS[@]}"; do echo "- $IP"; done)
    SERVICE_EXTERNAL_IP=$(cat <<-EOF | sed -r "s/-(.+)/    -\1/g"
	externalIPs:
	${IPS[@]}
	EOF
	)

    ## Kubernetes does not like args wth strings containing dashes, so we base64 encode it then later decode
    SSL_FULLCHAIN=$(consul kv get ssl/fullchain | base64)
    SSL_PRIVKEY=$(consul kv get ssl/privkey | base64)

    if [[ -z $SSL_FULLCHAIN || -z $SSL_PRIVKEY ]]; then
        echo "Could not find SSL certs in consul"

        if [[ -z $SSL_CERTS ]]; then
            echo "Using -s for SSL requires certs in consul kv ssl/fullchain and ssl/privkey"
            echo "or specifying certs dir using -c CERT_DIR. Exiting"
            exit
        fi

        SSL_FULLCHAIN=$(base64 < $SSL_CERTS/fullchain.pem)
        SSL_PRIVKEY=$(base64 < $SSL_CERTS/privkey.pem)
    fi
fi

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
    \n listen *:80;
    \n server_name *.'${ROOT_DOMAIN}';
    \n location /.well-known/ { return 302 "http://cert.'${ROOT_DOMAIN}':'${CERTPORT}'\$request_uri"; }
    \n '${COMMENT_IF_NO_SSL}'location / { return 302 https://\$host:443\$request_uri; }
    \n '${COMMENT_IF_SSL}'location / { proxy_pass "http://\$x"; }
    \n
}
\n
server {
    \n '${COMMENT_IF_NO_SSL}'listen *:443 ssl;
    \n server_name *.'${ROOT_DOMAIN}';
    \n ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4;
    \n server_tokens off; 
    \n ssl_prefer_server_ciphers on;
    \n '${COMMENT_IF_NO_SSL}'ssl_certificate     /etc/ssl/'${ROOT_DOMAIN}'/fullchain.pem;
    \n '${COMMENT_IF_NO_SSL}'ssl_certificate_key /etc/ssl/'${ROOT_DOMAIN}'/privkey.pem;
    \n location / { proxy_pass "http://\$x"; }
    \n
}\n'

##! PodDisruptionBudget policy available in kubernetes 1.21
##! #https://kubernetes.io/docs/tasks/run-application/configure-pdb/
#---
#apiVersion: policy/v1
#kind: PodDisruptionBudget
#metadata:
#  name: $APPNAME
#spec:
#  minAvailable: 1
#  selector:
#    matchLabels:
#      app: $APPNAME

#lifecycle:
#  preStop:
#    exec:
#      command: [
#        "sh", "-c",
#        # Introduce a delay to the shutdown sequence to wait for the
#        # pod eviction event to propagate. Then, gracefully shutdown
#        # nginx.
#        "sleep 5 && /usr/sbin/nginx -s quit",
#      ]
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
    - name: http
      protocol: TCP
      port: $HTTP_PORT
      targetPort: 80
      $SERVICE_NODEPORT
    $SSL_SERVICE
  $SERVICE_EXTERNAL_IP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APPNAME
  labels:
    app: $APPNAME
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2
      maxUnavailable: 1
  selector:
    matchLabels:
      app: $APPNAME
  template:
    metadata:
      labels:
        app: $APPNAME
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - $APPNAME
              topologyKey: "kubernetes.io/hostname"
            weight: 100
      containers:
      - name: $APPNAME
        image: $IMAGE:$TAG
        ports:
        - containerPort: 80
        - containerPort: 443
        volumeMounts:
        - mountPath: /etc/nginx/templates
          name: conf-volume
        - mountPath: /etc/ssl/${ROOT_DOMAIN}
          name: ssl-volume
      initContainers:
      - name: ${APPNAME}-init
        image: $IMAGE:$TAG
        command: ['/bin/sh', '-c']
        args:
          - 'printf "$NGINX_FILE" | tee /etc/nginx/templates/services.conf.template;
            printf "${SSL_PRIVKEY}" | base64 -d -i > /etc/ssl/${ROOT_DOMAIN}/privkey.pem;
            printf "${SSL_FULLCHAIN}" | base64 -d -i > /etc/ssl/${ROOT_DOMAIN}/fullchain.pem;'
        volumeMounts:
        - mountPath: /etc/nginx/templates
          name: conf-volume
        - mountPath: /etc/ssl/${ROOT_DOMAIN}
          name: ssl-volume
      volumes:
      - name: conf-volume
        emptyDir:
          medium: Memory
          sizeLimit: "2M"
      - name: ssl-volume
        emptyDir:
          medium: Memory
          sizeLimit: "2M"
EOF


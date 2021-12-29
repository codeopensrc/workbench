#!/bin/bash

MINIO_ROOT_USER=$(mc alias list azure --json | jq -r ".accessKey")
MINIO_ROOT_PASSWORD=$(mc alias list azure --json | jq -r ".secretKey")

while getopts "t:n:u:p:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        t) OPT_TAG=${OPTARG};;
        n) OPT_NODEPORT=${OPTARG};;
        u) MINIO_ROOT_USER=${OPTARG};;
        p) MINIO_ROOT_PASSWORD=${OPTARG};;
    esac
done


IMAGE=minio/minio
TAG="RELEASE.2021-12-27T07-23-18Z"
HTTP_PORT=80
APPNAME=minio-s3-gateway
NODEPORT=31900

if [[ -n $OPT_NODEPORT ]]; then NODEPORT=$OPT_NODEPORT; fi
if [[ -n $OPT_TAG ]]; then TAG=$OPT_TAG; fi;

echo "APPNAME: $APPNAME"
echo "IMAGE: $IMAGE"
echo "TAG: $TAG"
echo "NODEPORT: $NODEPORT"
#exit


SECRET_YAML=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $APPNAME
  labels:
    app: $APPNAME
type: Opaque
stringData:
    MINIO_ROOT_USER: ${MINIO_ROOT_USER}
    MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
EOF
)
echo "$SECRET_YAML" | kubectl apply -f -
SECRET_YAML_HASH=$(echo "$SECRET_YAML" | sha256sum)


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
      targetPort: 9000
      nodePort: $NODEPORT
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
        command: ["minio"]
        args: ["gateway", "azure"]
        ports:
        - containerPort: 9000
        envFrom:
        - secretRef:
            name: $APPNAME
EOF


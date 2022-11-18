#!/bin/bash

## TODO: Add a pipeline for workbench to manually run and do this

if [[ -n $2 ]]; then
    TAG=$1
    IMAGE=$2
else
    TAG=$1
    IMAGE=registry.codeopensrc.com/os/workbench/kube
fi

echo "TAG $TAG"
echo "IMAGE $IMAGE"

BUILDKITD_POD=buildkitd-0
BUILDKITD_NAMESPACE=buildkitd
DOCKERFILE=k8s.Dockerfile
OUTPUT_IMGS="${IMAGE}:${TAG}"

buildctl --addr kube-pod://${BUILDKITD_POD}?namespace=${BUILDKITD_NAMESPACE} \
    build \
    --frontend dockerfile.v0 --local dockerfile=. --local context=. \
    --opt filename=./${DOCKERFILE} \
    --opt build-arg:KUBE_VERSION=$TAG \
    --import-cache type=registry,ref=${OUTPUT_IMGS} \
    --export-cache type=inline \
    --output type=image,\"name=${OUTPUT_IMGS}\",push=true

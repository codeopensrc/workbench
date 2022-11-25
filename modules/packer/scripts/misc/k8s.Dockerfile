ARG BASE_IMAGE=alpine
ARG BASE_IMAGE_TAG=3.14

FROM ${BASE_IMAGE}:${BASE_IMAGE_TAG}

ARG KUBE_VERSION=1.24.7
ARG HELM_VERSION=3.8.2
ARG SKAFFOLD_VERSION=2.0.0
ARG BUILDCTL_VERSION=0.10.5
ENV KUBE_VERSION=$KUBE_VERSION
ENV HELM_VERSION=$HELM_VERSION
ENV SKAFFOLD_VERSION=$SKAFFOLD_VERSION
ENV BUILDCTL_VERSION=$BUILDCTL_VERSION

RUN apk add --update ca-certificates \
    && apk add --update bash git curl jq \
    && curl -L https://dl.k8s.io/release/v${KUBE_VERSION}/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
    && chmod g+rwx /usr/local/bin/kubectl \
    && curl -L https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz -o /tmp/helm-linux.tar.gz \
    && tar -xzvf /tmp/helm-linux.tar.gz --directory /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && curl -L https://storage.googleapis.com/skaffold/releases/v${SKAFFOLD_VERSION}/skaffold-linux-amd64 -o /tmp/skaffold-linux \
    && install /tmp/skaffold-linux /usr/local/bin/skaffold \
    && curl -L https://github.com/moby/buildkit/releases/download/v${BUILDCTL_VERSION}/buildkit-v${BUILDCTL_VERSION}.linux-amd64.tar.gz -o /tmp/buildkit-linux.tar.gz \
    && mkdir -p /tmp/buildkit-linux && tar -xzvf /tmp/buildkit-linux.tar.gz -C /tmp/buildkit-linux \
    && mv /tmp/buildkit-linux/bin/buildctl /usr/local/bin \
    && rm -rf /tmp/*linux* \
    && rm /var/cache/apk/*

ENTRYPOINT ["bash"]
CMD [""]

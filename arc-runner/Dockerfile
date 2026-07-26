# Runner image for the ARC scale set used by .github/workflows/core.yml.
#
# The workflow assumes every CLI it needs is already on PATH, so this image
# bakes in helm, kubectl, helmfile and the helm-diff plugin that `helmfile
# apply` depends on. Versions are pinned and overridable via --build-arg.
#
# Build and push (the lab nodes are arm64 Raspberry Pis):
#   docker buildx build --platform linux/arm64 \
#     --tag ghcr.io/sondn98/fabricator-arc-runner:2.336.0 \
#     --push docker/arc-runner
#
# Then point the scale set at the pushed tag in core/arc/values.yaml:
#   gha-runner-scale-set.template.spec.containers[0].image
#
# The base image already ships curl, git and tar, so no apt work is needed here.

ARG RUNNER_VERSION=2.336.0

FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

ARG HELM_VERSION=v3.21.3
ARG KUBECTL_VERSION=v1.34.10
ARG HELMFILE_VERSION=1.7.1
ARG HELM_DIFF_VERSION=3.15.10
# Set automatically by BuildKit; the default keeps a plain `docker build` working.
ARG TARGETARCH=arm64

USER root

RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" -o /tmp/helm.tar.gz \
    && tar -xzf /tmp/helm.tar.gz -C /tmp "linux-${TARGETARCH}/helm" \
    && install -m 0755 "/tmp/linux-${TARGETARCH}/helm" /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz "/tmp/linux-${TARGETARCH}"

RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" -o /tmp/kubectl \
    && install -m 0755 /tmp/kubectl /usr/local/bin/kubectl \
    && rm -f /tmp/kubectl

RUN curl -fsSL "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_${TARGETARCH}.tar.gz" -o /tmp/helmfile.tar.gz \
    && tar -xzf /tmp/helmfile.tar.gz -C /tmp helmfile \
    && install -m 0755 /tmp/helmfile /usr/local/bin/helmfile \
    && rm -f /tmp/helmfile.tar.gz /tmp/helmfile

# helm-diff is installed as - and owned by - the `runner` user the runner
# process executes as, so HimageELM_PLUGINS resolves it when helmfile shells out.
ENV HELM_PLUGINS=/home/runner/.local/share/helm/plugins

USER runner

RUN helm plugin install https://github.com/databus23/helm-diff --version "v${HELM_DIFF_VERSION}" \
    && rm -rf /home/runner/.cache/helm

WORKDIR /home/runner

ARG HARNESS_UBUNTU_IMAGE=ubuntu:24.04
FROM ${HARNESS_UBUNTU_IMAGE}

ARG HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL=simulation-only
RUN printf 'public_internet_fallback=%s\n' "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL" > /etc/harness-source-boundary && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      fontconfig \
      git \
      ldap-utils \
      net-tools \
      netcat-openbsd \
      openjdk-21-jre \
      openssh-client \
      openssh-server \
      procps \
      rsync \
      tar \
      unzip \
      wget && \
    groupadd --system gerrit && \
    useradd --system --gid gerrit --home-dir /harness/state/site --shell /bin/bash gerrit && \
    groupadd --system jenkins && \
    useradd --system --gid jenkins --home-dir /harness/state/jenkins-home --shell /bin/bash jenkins && \
    rm -rf /var/lib/apt/lists/*

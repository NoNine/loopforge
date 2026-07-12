ARG HARNESS_UBUNTU_IMAGE=ubuntu:24.04
FROM ${HARNESS_UBUNTU_IMAGE}

ARG HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL=simulation-only
RUN printf 'public_internet_fallback=%s\n' "$HARNESS_PUBLIC_INTERNET_FALLBACK_LABEL" > /etc/harness-source-boundary && \
    sed -i \
      -e 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.tuna.tsinghua.edu.cn/ubuntu/|g' \
      -e 's|http://security.ubuntu.com/ubuntu/|http://mirrors.tuna.tsinghua.edu.cn/ubuntu/|g' \
      /etc/apt/sources.list.d/ubuntu.sources && \
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
      sudo \
      tar \
      tree \
      unzip \
      wget && \
    groupadd --gid 61010 gerrit && \
    useradd --uid 61010 --gid 61010 --home-dir /srv/gerrit --shell /bin/bash gerrit && \
    groupadd --gid 61020 jenkins && \
    useradd --uid 61020 --gid 61020 --home-dir /var/lib/jenkins --shell /bin/bash jenkins && \
    groupadd --gid 61030 jenkins-agent && \
    useradd --uid 61030 --gid 61030 --home-dir /var/lib/jenkins-agent --shell /bin/bash jenkins-agent && \
    groupadd --gid 61000 ci-operator && \
    useradd --uid 61000 --create-home --gid 61000 --home-dir /home/ci-operator --shell /bin/bash ci-operator && \
    printf '%s\n' 'ci-operator ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/harness-ci-operator && \
    chmod 0440 /etc/sudoers.d/harness-ci-operator && \
    visudo -cf /etc/sudoers.d/harness-ci-operator && \
    rm -rf /var/lib/apt/lists/*

ARG LOOPFORGE_RESOURCE=docker-simulation
ARG LOOPFORGE_SCHEMA_VERSION=1
ARG LOOPFORGE_PROJECT=unknown
ARG LOOPFORGE_RUN_ID=unknown
ARG LOOPFORGE_SERVICE=unknown
LABEL org.loopforge.resource="${LOOPFORGE_RESOURCE}" \
      org.loopforge.schema-version="${LOOPFORGE_SCHEMA_VERSION}" \
      org.loopforge.project="${LOOPFORGE_PROJECT}" \
      org.loopforge.run-id="${LOOPFORGE_RUN_ID}" \
      org.loopforge.service="${LOOPFORGE_SERVICE}"

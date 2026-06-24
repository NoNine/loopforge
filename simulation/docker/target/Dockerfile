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
      unzip \
      wget && \
    groupadd --system gerrit && \
    useradd --system --gid gerrit --home-dir /srv/gerrit --shell /bin/bash gerrit && \
    groupadd --system jenkins && \
    useradd --system --gid jenkins --home-dir /var/lib/jenkins --shell /bin/bash jenkins && \
    groupadd --system jenkins-agent && \
    useradd --system --gid jenkins-agent --home-dir /var/lib/jenkins-agent --shell /bin/bash jenkins-agent && \
    groupadd --system ci-operator && \
    useradd --create-home --gid ci-operator --home-dir /home/ci-operator --shell /bin/bash ci-operator && \
    printf '%s\n' 'ci-operator ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/harness-ci-operator && \
    chmod 0440 /etc/sudoers.d/harness-ci-operator && \
    visudo -cf /etc/sudoers.d/harness-ci-operator && \
    rm -rf /var/lib/apt/lists/*

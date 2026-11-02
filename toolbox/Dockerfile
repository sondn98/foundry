
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/toolbox
ENV PATH="/usr/local/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    wget \
    git \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    yq \
    dnsutils \
    iproute2 \
    iputils-ping \
    iputils-tracepath \
    net-tools \
    netcat-openbsd \
    socat \
    tcpdump \
    tshark \
    nmap \
    mtr-tiny \
    traceroute \
    iperf3 \
    ethtool \
    conntrack \
    iptables \
    openssl \
    procps \
    htop \
    sysstat \
    strace \
    lsof \
    vim-tiny \
    less \
    file \
    unzip \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN groupadd -g 10001 toolbox \
    && useradd -u 10001 -g toolbox \
       -m -d /home/toolbox -s /bin/bash toolbox \
    && mkdir -p /tmp/toolbox \
    && chown -R 10001:10001 /home/toolbox /tmp/toolbox

USER 10001:10001

WORKDIR /home/toolbox

CMD ["sleep", "infinity"]

FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gpg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && printf '%s' "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        bc \
        bison \
        build-essential \
        ccache \
        cpio \
        cgpt \
        device-tree-compiler \
        docker-ce \
        dosfstools \
        e2fsprogs \
        erofs-utils \
        file \
        flex \
        gawk \
        gdisk \
        gettext \
        git \
        jq \
        libelf-dev \
        libncurses-dev \
        libssl-dev \
        linux-base \
        lz4 \
        make \
        parted \
        patch \
        perl \
        python3 \
        python3-pkg-resources \
        python3-setuptools \
        rsync \
        skopeo \
        squashfs-tools \
        sudo \
        u-boot-tools \
        unzip \
        vboot-kernel-utils \
        vboot-utils \
        wget \
        xxd \
        xz-utils \
        zstd \
    && wget -q -O /tmp/depthcharge-tools.deb http://deb.debian.org/debian/pool/main/d/depthcharge-tools/depthcharge-tools_0.6.2-2_all.deb \
    && apt-get install -y --no-install-recommends /tmp/depthcharge-tools.deb \
    && rm -f /tmp/depthcharge-tools.deb \
    && rm -rf /var/lib/apt/lists/*

COPY docker/haos-builder/entry.sh /usr/sbin/haos-builder-entry.sh
RUN chmod 0755 /usr/sbin/haos-builder-entry.sh

WORKDIR /build

ENTRYPOINT ["/usr/sbin/haos-builder-entry.sh"]

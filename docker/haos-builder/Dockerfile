FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        bc \
        bison \
        build-essential \
        ca-certificates \
        ccache \
        cpio \
        curl \
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
        make \
        parted \
        patch \
        perl \
        python3 \
        python3-setuptools \
        rsync \
        skopeo \
        squashfs-tools \
        unzip \
        wget \
        xxd \
        xz-utils \
        zstd \
    && if apt-cache show vboot-utils >/dev/null 2>&1; then \
        apt-get install -y --no-install-recommends vboot-utils; \
    else \
        apt-get install -y --no-install-recommends vboot-kernel-utils; \
    fi \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

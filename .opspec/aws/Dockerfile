FROM ubuntu:bionic
label Maintainer="Jim Conner <snafu.x@gmail.com,james.c@samsung.com>",
label copyright="(c) 2018 Samsung Corp."
label license="Apache2 license: https://www.apache.org/licenses"

VOLUME /var/tmp/work
WORKDIR /var/tmp/work

RUN DEBIAN_FRONTEND=noninteractive && \
    apt update && \
    apt install -y bash python-pip openssh-client wget gettext curl jq git ruby apt-transport-https && \
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list && \
    apt update && apt install -y kubectl && \
    pip install awscli && \
    find /usr/local \
           \( -type d -a -name test -o -name tests \) \
        -o \( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
        -exec rm -rf '{}' + && \
    apt autoremove && apt autoclean && \
    apt purge -y python-pip

RUN curl -sSLO 'https://github.com/jpmens/jo/releases/download/v1.1/jo-1.1.tar.gz' && \
    tar xfz jo-1.1.tar.gz && \
    cd jo* && \
    ./configure && \
    make && \
    make install

# kinda kludgy, but it turns out that ssh from within a container is hokey.
ARG HOME
ARG OWNER_USER
ARG OWNER_UID
ARG OWNER_GID
RUN printenv
RUN addgroup --gid $OWNER_GID $OWNER_USER && \
    adduser --system $OWNER_USER --uid $OWNER_UID --gid $OWNER_GID --shell /bin/bash && \
    chown -R $OWNER_UID:$OWNER_GID $HOME/

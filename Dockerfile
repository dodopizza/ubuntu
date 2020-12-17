FROM alpine:3.10.3 AS jsonnet_builder
WORKDIR /workdir
RUN apk -U add build-base git \
    && git clone https://github.com/google/jsonnet . \
    && export LDFLAGS=-static \
    && make

FROM ubuntu:20.04

LABEL maintainer="Vitaly Uvarov <v.uvarov@dodopizza.com>"

ENV DEBIAN_FRONTEND=noninteractive

COPY --from=jsonnet_builder /workdir/jsonnet /usr/local/bin/
COPY --from=jsonnet_builder /workdir/jsonnetfmt /usr/local/bin/
COPY --from=innotop_builder /usr/local/bin/innotop /usr/local/bin/

RUN apt-get update \
    && apt-get install -y vim htop curl unzip git jq python3.8 python3.8-dev python3-distutils \
    && apt-get clean \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1 \
    && curl https://bootstrap.pypa.io/get-pip.py | python \
    && pip --no-cache-dir install --upgrade pip \
    && pip --no-cache-dir install yq

## expect && pexpect
RUN apt-get install -y expect \
    && pip --no-cache-dir install pexpect==4.7.0 \
    && apt-get clean

## Debug available versions
RUN pip --no-cache-dir install yolk3k \
    && yolk -V ansible \
    && yolk -V azure-cli

## azure-cli
RUN apt-get install -y gcc \
    && pip --no-cache-dir install 'azure-cli==2.16.0' \
    && apt-get remove -y gcc

## azure kubernetes client
RUN az aks install-cli

## ansible
RUN pip --no-cache-dir install \
    'ansible==2.10.4' \
    'ansible-lint' \
    'pywinrm>=0.3.0' \
    'requests-ntlm'

## azcopy10
RUN cd /tmp/ \
    && curl -L https://aka.ms/downloadazcopy-v10-linux | tar --strip-components 1 -xz \
    && mv -f /tmp/azcopy /usr/bin/

## mysql client + percona tools
RUN apt-get install -y gnupg2 lsb-release wget \
    && wget https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb \
    && dpkg -i percona-release_latest.$(lsb_release -sc)_all.deb \
    && apt-get update \
    && apt-get install -y percona-server-client-5.7 percona-toolkit percona-xtrabackup-24 \
    && apt-get clean

## azure mysqlpump binary (5.6 issue)
COPY bin/az-mysqlpump /usr/local/bin/

## docker-client for dind
RUN apt-get install -y apt-transport-https ca-certificates gnupg-agent software-properties-common \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
    && apt-key fingerprint 0EBFCD88 \
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && apt-get clean

## docker-compose for dind
RUN pip install docker-compose

## packer (hashicorp-packer) 
## https://github.com/hashicorp/packer/releases
## issue: https://github.com/cracklib/cracklib/issues/7
RUN packer_version=1.6.5 \
    && curl -o /tmp/packer.zip https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_amd64.zip \
    && unzip /tmp/packer.zip -d /tmp/ \
    && mv -f /tmp/packer /usr/bin/hashicorp-packer \
    && rm -f /tmp/packer.zip

## bin/pt-online-schema-change temporary patch
RUN pt-online-schema-change --version || true
COPY bin/pt-online-schema-change-3.0.14-dev /usr/bin/pt-online-schema-change

## bin/gh-ost temporary patch
COPY bin/gh-ost /usr/bin/gh-ost

## ghost-tool from dodopizza/sre-toolchain
COPY bin/ghost-tool.sh  /usr/bin/ghost-tool
RUN  ln -s /usr/bin/ghost-tool /usr/bin/gh-ost-tool

## helm
RUN cd /tmp/ \
    && helm_version=2.11.0 \
    && curl -L https://get.helm.sh/helm-v${helm_version}-linux-amd64.tar.gz | tar zx \
    && mv -f linux-amd64/helm /usr/bin/helm${helm_version} \
    && ln -f -s /usr/bin/helm${helm_version} /usr/bin/helm \
    && rm -rf linux-amd64

## werf
## https://github.com/flant/werf/releases
RUN werf_version=1.2.2+fix4 \
    && curl -L https://dl.bintray.com/flant/werf/v${werf_version}/werf-linux-amd64-v${werf_version} -o /tmp/werf \
    && chmod +x /tmp/werf \
    && mv /tmp/werf /usr/local/bin/werf

## promtool from prometheus
## https://github.com/prometheus/prometheus/releases
RUN cd /tmp/ \
    && prometheus_version=2.21.0 \
    && curl -L https://github.com/prometheus/prometheus/releases/download/v${prometheus_version}/prometheus-${prometheus_version}.linux-amd64.tar.gz | tar zx \
    && cp -f prometheus-${prometheus_version}.linux-amd64/promtool /usr/bin/ \
    && rm -rf prometheus-${prometheus_version}.linux-amd64

## terraform
## https://releases.hashicorp.com/terraform
RUN terraform_version=0.14.2 \
    && curl -o /tmp/terraform.zip https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip \
    && unzip /tmp/terraform.zip -d /usr/bin/ \
    && rm -f /tmp/terraform.zip

# ## scaleft client
RUN echo "deb http://pkg.scaleft.com/deb linux main" | tee -a /etc/apt/sources.list \
    && curl -C - https://dist.scaleft.com/pki/scaleft_deb_key.asc | apt-key add - \
    && apt-get update \
    && apt-get install -y scaleft-client-tools \
    && mkdir /root/.ssh && sft ssh-config > /root/.ssh/config \
    && apt-get clean

## redis-cli
COPY bin/redis-cli /usr/bin/redis-cli

## innotop
RUN cd /tmp/ \
    && apt-get update \
    && apt-get install -y git make libdbi-perl \
    && git clone https://github.com/innotop/innotop.git \
    && cd innotop/ \
    && perl Makefile.PL \
    && make install \
    && innotop --version

## scaleft user forwarding from host machine to container
COPY  scripts/docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/bin/bash"]

## bash aliases
COPY scripts/bash-aliases.sh /
RUN echo -e '\nsource /bash-aliases.sh' >> ~/.bashrc

## version info for changelog
COPY scripts/version-info.sh /
RUN /version-info.sh

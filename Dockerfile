FROM debian:10.1

LABEL maintainer="alitari67@gmail.com"

# Configure apt
ENV DEBIAN_FRONTEND=noninteractive

# install the tools i wish to use
RUN apt-get update && \
  apt-get install -y sudo \
  curl \
  git-core \
  locales \
  wget \
  bash-completion \
  vim \
  gettext-base \
  jq \
  dialog \
  dnsutils \
  && locale-gen en_US.UTF-8

# Switch back to dialog for any ad-hoc use of apt-get
ENV DEBIAN_FRONTEND=dialog

ENV USER_NAME alitari
ENV USER_PASSWORD password

# add a user (--disabled-password: the user won't be able to use the account until the password is set)
RUN adduser --quiet --disabled-password --shell /bin/zsh --home /home/$USER_NAME --gecos "User" $USER_NAME
# update the password
RUN echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd && usermod -aG sudo $USER_NAME
RUN echo $USER_NAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USER_NAME && chmod 0440 /etc/sudoers.d/$USER_NAME

ENV TERM xterm

# Set the default shell to bash rather than sh
ENV SHELL /bin/bash

# kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.16.0/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl


# cluster config
RUN mkdir /home/alitari/.kube
ADD .devcontainer/config /home/alitari/.kube/
RUN chmod 777 -R /home/alitari/.kube

# helm
RUN curl -LO https://get.helm.sh/helm-v3.0.2-linux-amd64.tar.gz \
    && tar xfv helm-v3.0.2-linux-amd64.tar.gz \
    && chmod a+x linux-amd64/helm \
    && mv linux-amd64/helm /usr/local/bin/helm \
    && rm -rf linux-amd64/ \
    && rm helm-v3.0.2-linux-amd64.tar.gz


# set home
ENV HOME /home/$USER_NAME

ADD ingress-installer.sh /
RUN chmod +x /ingress-installer.sh
CMD /ingress-installer.sh

# the user we're applying this too (otherwise it most likely install for root)
USER $USER_NAME

# krew
RUN ( \
    set -x; cd "$(mktemp -d)" && \
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/v0.3.3/krew.{tar.gz,yaml}" && \
    tar zxvf krew.tar.gz && \ 
    KREW=./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" && \
    "$KREW" install --manifest=krew.yaml --archive=krew.tar.gz && \
    "$KREW" update )
ENV PATH="${HOME}/.krew/bin:${PATH}"

RUN kubectl krew install ns

# install rio cli
RUN curl -sfL https://get.rio.io | sh -

# bash configuration
ADD .devcontainer/.bashrc /home/alitari

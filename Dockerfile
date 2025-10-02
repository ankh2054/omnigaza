# syntax=docker/dockerfile:1
FROM ubuntu:22.04

ARG USER_ID
ARG GROUP_ID
ARG ORG="AntelopeIO"

# Update these to match releases; contracts can be a full git commit hash.
ARG SPRING_VERSION=latest
ARG CDT_VERSION=latest
ARG CONTRACTS_VERSION=latest

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
# Ensure global npm installs land on PATH
ENV NPM_CONFIG_PREFIX=/usr/local

#Check which version 
RUN dpkg --print-architecture && uname -m

# Base tooling (including nodejs & npm from Ubuntu repos)
# If you need newer Node, swap to NodeSource or the official node image.
RUN apt-get update && \
    apt-get -y install --no-install-recommends \
      tzdata \
      zip unzip libncurses5 wget git build-essential cmake curl \
      libboost-all-dev libcurl4-gnutls-dev libgmp-dev libssl-dev \
      libusb-1.0.0-dev libzstd-dev time pkg-config llvm-11-dev \
      nginx nodejs npm yarn jq gdb lldb ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Install webpack toolchain globally to avoid running npm in /
RUN npm cache clean --force && \
    npm install -g webpack webpack-cli webpack-dev-server --no-audit --no-fund

# From here on, work inside /app
WORKDIR /app

# Copy the scripts
COPY ./scripts/ .
RUN chmod +x *.sh

# Install your software
RUN ./bootstrap_leap.sh "$SPRING_VERSION"
RUN ./bootstrap_cdt.sh "$CDT_VERSION"
RUN ./bootstrap_contracts.sh "$CONTRACTS_VERSION"

RUN mkdir -p /app/nodes

# thanks to github.com/phusion
# this should solve reaping issues of stopped nodes
CMD ["tail", "-f", "/dev/null"]

# Exposed ports
# port for nodeos p2p
EXPOSE 9876
# port for nodeos http
EXPOSE 8888
# port for state history
EXPOSE 8080
# port for webapp
EXPOSE 8000
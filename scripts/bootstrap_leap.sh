#! /bin/sh -e
#
# install_spring.sh
#
# This script will install the spring .deb package with version as provided in $1.
# If $1 is 'latest', the latest release is used.
#

# Make sure we operate in the expected directory.
cd "$(dirname "$(readlink -f "$0")")"

# Sanity check
if [ -z "$ORG" ]; then
    ORG="AntelopeIO"
fi

# Sanity check version, set the variable.
if [ -z "$1" ]; then
    echo "arg 1, spring version, is empty."
    exit 1
fi
VERSION=$1
# Allow latest as an option in case insensitive fashion.
if [ "$(echo "${VERSION}" | tr "[:lower:]" "[:upper:]")" = "LATEST" ]; then
    VERSION=$(wget -q -O- https://api.github.com/repos/"$ORG"/spring/releases/latest | jq -r '.tag_name' | cut -c2-)
fi

# Install latest spring release

spring_PKG=antelope-spring_"${VERSION}"_amd64.deb
spring_DEV_PKG=antelope-spring-spring-dev_"${VERSION}"_amd64.deb
wget https://github.com/"${ORG}"/spring/releases/download/v"${VERSION}"/"${spring_PKG}"


# Get the package and install it
apt --assume-yes --allow-downgrades install ./"${spring_PKG}"


# Remove any downloaded packages.
rm -f spring*ubuntu*.deb || true

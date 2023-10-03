#!/usr/bin/env bash
set -o pipefail
set -o nounset
set -o errexit

if [ "$NVIDIA_BUILD" = "true" ]; then
  echo "Installing EFA"
else
  echo "Skipping install EFA in standard AMI build"
  exit 0
fi

if vercmp "$KUBERNETES_VERSION" lt "1.27.0"; then
  echo "Skip EFA installation as $KUBERNETES_VERSION lower than 1.27"
  exit 0
fi

## Setup
## EFA installation for classic region, https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html#efa-start-enable
EFA_VERSION="latest"
EFA_PACKAGE="aws-efa-installer-${EFA_VERSION}.tar.gz"
EFA_DOMAIN="https://efa-installer.amazonaws.com"

# referring the following docs for ADC installation
# DCA: https://dca-docs-aws.corp.amazon.com/AWSEC2/latest/UserGuide/efa-start.html
# LCK: https://lck-docs-aws.corp.amazon.com/AWSEC2/latest/UserGuide/efa-start.html
ISOLATED_REGIONS="${ISOLATED_REGIONS:-us-iso-east-1 us-iso-west-1}"
if [[ ${ISOLATED_REGIONS} =~ $AWS_REGION ]]; then
  EFA_DOMAIN="https://aws-efa-installer.s3.${AWS_REGION}.c2s.ic.gov"
elif [ "$AWS_REGION" == "us-isob-east-1" ]; then
  EFA_DOMAIN="https://aws-efa-installer.s3.${AWS_REGION}.sc2s.sgov.gov"
fi

mkdir -p /tmp/efa-installer
cd /tmp/efa-installer

## Download Installer
curl -O ${EFA_DOMAIN}/${EFA_PACKAGE}

## Signature verification
curl -O ${EFA_DOMAIN}/aws-efa-installer.key && gpg --import aws-efa-installer.key
curl -O ${EFA_DOMAIN}/${EFA_PACKAGE}.sig
if ! gpg --verify ./aws-efa-installer-${EFA_VERSION}.tar.gz.sig &> siginfo ;then
    echo "EFA Installer signature failed verification!"
    exit 2
fi

## Extract and Install
tar -xf ${EFA_PACKAGE} && cd aws-efa-installer
sudo ./efa_installer.sh -y

## Cleanup
cd -
rm -rf /tmp/efa-installer
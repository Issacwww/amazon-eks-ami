#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit
IFS=$'\n\t'
## Switch NVIDIA_BUILD, if this is true then run the following code to install nvidia, otherwise skip it for the non-GPU ami build
if [ "$NVIDIA_BUILD" = "true" ]; then
  echo "Installing Nvidia drivers support..."
else
  echo "Skipping install Nvidia drivers in standard AMI build"
  exit 0
fi

TEMPLATE_DIR=$WORKING_DIR/nvidia
################################################################################
### Enable repos ###############################################################
################################################################################

## override the NVIDIA_MAJOR_VERSION by KUBERNETES_VERSION
## TODO: remove this once backport all KUBERNETES_VERSION with 535 driver
K8S_VERSION_SUPPORTS_LATEST_NVIDIA_DRIVER="1.27.0"
if vercmp "$KUBERNETES_VERSION" lt "$K8S_VERSION_SUPPORTS_LATEST_NVIDIA_DRIVER"; then
  NVIDIA_MAJOR_VERSION="470"
fi

if [ -z "$NVIDIA_MAJOR_VERSION" ] || ! [[ $NVIDIA_MAJOR_VERSION =~ ^[0-9]+$ ]]; then
    echo "Invalid nvidia major version number"
    exit 1
fi

if [ $NVIDIA_MAJOR_VERSION -ge "535" ]; then
  NVIDIA_REPO=amzn2-nvidia.repo
  CUDA_MAJOR_VERSION="12"
else
  echo "Switching to 470 branch repo for $KUBERNETES_VERSION"
  NVIDIA_REPO=amzn2-nvidia-470-branch.repo
  CUDA_MAJOR_VERSION="11"
fi

ISOLATED_REGIONS="${ISOLATED_REGIONS:-us-iso-east-1 us-iso-west-1 us-isob-east-1}"
if [[ ${ISOLATED_REGIONS} =~ $AWS_REGION ]]; then
  NVIDIA_REPO="iso-$NVIDIA_REPO"
fi

sudo mv $TEMPLATE_DIR/$NVIDIA_REPO \
  /etc/yum.repos.d/$NVIDIA_REPO

sudo yum install -y system-release-nvidia

if [ $NVIDIA_MAJOR_VERSION -lt "535" ]; then
  # `system-release-nvidia` will pull the latest nvidia repo back and will result into installing 535 driver
  NVIDIA_REPO_TO_REMOVE="/etc/yum.repos.d/amzn2-nvidia.repo"
  [ -f $NVIDIA_REPO_TO_REMOVE ] && sudo rm -f $NVIDIA_REPO_TO_REMOVE
fi
echo "Installing nvidia packages with $NVIDIA_MAJOR_VERSION and cuda with $CUDA_MAJOR_VERSION ..."

################################################################################
### Install Nvidia drivers and container runtime ###############################
################################################################################

# Referring to EC2 doc to add the following
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start-nccl-base.html
if vercmp "$KERNEL_VERSION" gteq "5.10"; then
  sudo mkdir -p /etc/dkms \
    && echo "MAKE[0]=\"'make' -j2 module SYSSRC=\${kernel_source_dir} IGNORE_XEN_PRESENCE=1 IGNORE_PREEMPT_RT_PRESENCE=1 IGNORE_CC_MISMATCH=1 CC=/usr/bin/gcc10-gcc\"" | sudo tee /etc/dkms/nvidia.conf
fi

# Nvidia recommends installing these packages before cuda/cuda-drivers/fabricmanager
sudo yum install -y kmod-nvidia-latest-dkms \
  nvidia-driver-latest-dkms

sudo yum versionlock \
  nvidia-driver-latest-dkms-* \
  kmod-nvidia-latest-dkms-*

sudo yum install -y cuda-drivers-fabricmanager \
  cuda-drivers \
  cuda

# https://github.com/NVIDIA/nvidia-container-runtime/releases/tag/3.1.0
# We've renamed nvidia-container-runtime-hook to nvidia-container-toolkit as this is now the package new users
# are expected to install. For more details see the nvidia-docker2 readme: https://github.com/NVIDIA/nvidia-docker

# docker-runtime-nvidia is Amazon internal package
# docker-runtime-nvidia dependencies include nvidia-container-runtime, xorg-x11-server-Xorg
# TODO: remove the docker and install containerd directly for 1.28+
sudo yum install -y docker-runtime-nvidia

## Version lock both Docker, nvidia-docker2 and containerd (otherwise this gets upgraded and leads to conflicts)
sudo yum versionlock \
  nvidia-container-runtime-* \
  cuda-drivers-fabricmanager-* \
  cuda-drivers-* cuda-*

# enable fabric manager
sudo systemctl enable nvidia-fabricmanager

# This fix will be needed for 1.27 and below as those version still using the 470-branch repo that not contains this fix
# https://github.com/NVIDIA/yum-packaging-nvidia-driver/pull/5/files
# This does no harm to 1.28+ versions, and we can remove this once all AMI move to 535 branch repo
sudo sed -i 's/GRUB_CMDLINE_LINUX=nouveau.modeset=0 rd.driver.blacklist=nouveau/GRUB_CMDLINE_LINUX="nouveau.modeset=0 rd.driver.blacklist=nouveau"/g' /etc/default/grub


################################################################################
### Nvidia drivers and container runtime version validation ####################
################################################################################

function validate_nvidia_package_versions() {

  # Manually initialize the associative array (map)
  declare -A expected_versions=(
    ["nvidia-driver-latest-dkms"]=$NVIDIA_MAJOR_VERSION
    ["kmod-nvidia-latest-dkms"]=$NVIDIA_MAJOR_VERSION
    ["cuda-drivers-fabricmanager"]=$NVIDIA_MAJOR_VERSION
    ["cuda-drivers"]=$NVIDIA_MAJOR_VERSION
    ["cuda"]=$CUDA_MAJOR_VERSION
  )

  # Loop through the keys in the map and validate
  for package in "${!expected_versions[@]}"; do
    version=${expected_versions[$package]}
    full_package_version="${package}-${version}.*"

    if ! rpm --query "$full_package_version" &> /dev/null; then
      installed_version=$(rpm --query "${package}" | grep -Eo "${package}-[0-9]*" | sed "s/${package}-//")
      echo "Mismatch for $package. Expected version: $version.x.x but found version: $installed_version"
      exit 1
    fi
  done

  echo "All package versions are correct!"
}

if ! cat /etc/*release | grep "al2023" > /dev/null 2>&1; then
  echo "Verifying that the nvidia package versions are correct..."
  validate_nvidia_package_versions
fi

##
## Show Nvidia EULA as part of Nvidia service startup
##
sudo mv $TEMPLATE_DIR/nvidia-eula /etc/eks/
sudo chmod +x /etc/eks/nvidia-eula
sudo mv $TEMPLATE_DIR/nvidia-eula.service /etc/systemd/system/


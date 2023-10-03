#!/usr/bin/env bash
set -o pipefail
set -o nounset
set -o errexit

if [ "$NVIDIA_BUILD" = "false" ]; then
  echo "Skipping c-state limiting in standard AMI build"
  exit 0
fi

if vercmp "$KUBERNETES_VERSION" gteq "1.27.0"; then
  echo "Limiting deeper C-states for 1.27 and above GPU"
  sudo grubby \
    --update-kernel=ALL \
    --args="intel_idle.max_cstate=1 processor.max_cstate=1"
fi

sudo reboot
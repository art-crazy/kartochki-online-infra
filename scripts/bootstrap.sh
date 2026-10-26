#!/usr/bin/env bash
# Compatibility entry point: host provisioning now belongs to vps-infra.
set -Eeuo pipefail
echo 'Prepare the host using art-crazy/vps-infra/docs/new-host.md first.' >&2
echo 'Then install this project using scripts/install-project.sh or setup-server.yml.' >&2
exit 2

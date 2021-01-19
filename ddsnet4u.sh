#!/usr/bin/env bash

set -e

subnet=(
  "139.229.147.0/24 via 139.229.170.254 dev net1"
  "139.229.166.0/24 via 139.229.170.254 dev net1"
  "139.229.167.0/24 via 139.229.170.254 dev net1"
  "139.229.178.0/24 via 139.229.170.254 dev net1"
)

# assume that if net1 interface doesn't exist, that multus isn't in volved with this pod.
[[ ! -e /sys/class/net/net1 ]] && exit 0

for s in "${subnet[@]}"; do
  # check if route exists
  if ! ip route | grep "${s}" > /dev/null 2>&1; then
    # if not, inject it
    # shellcheck disable=SC2086 # allow word splitting of ${s}
    ip route add ${s}
  fi
done

# vim: tabstop=2 shiftwidth=2 expandtab

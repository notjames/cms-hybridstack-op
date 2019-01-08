#!/bin/bash

# if cluster_id specified on CLI at runtime, it takes precedence.
if [[ -n "$_cluster_id" && "$_cluster_id" != "nil" ]]; then
  CLUSTER_ID=$_cluster_id
fi

if [[ -n "$_os_type" && "$_os_type" != "nil" ]]; then
  OS_TYPE=$_os_type
fi

if [[ $CLUSTER_ID == "nil" ]]; then
  echo >&2 "CLUSTER_ID was neither set nor specified. Cannot continue."
  exit 22
fi

if [[ $OS_TYPE == "nil" ]]; then
  echo >&2 "OS_TYPE was neither set nor specified. Cannot continue."
  exit 21
fi

pids=()
c=0

# shellcheck disable=SC2034
for CLUSTER_TYPE in manager managed; do
  bin/run-cloud-formation.sh &
  pids[$c]=$!
  ((c++))
  # this sleep is necessary! Keep it or key creation/import will fail
  sleep 5
done

for pid in "${pids[@]}"; do
  wait $pid
done

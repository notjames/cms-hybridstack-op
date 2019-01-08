#!/bin/bash

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

. bin/aws_key_management.sh
b64_encoded_key
echo "CLUSTER_PRIVATE_KEY=$CLUSTER_PRIVATE_KEY"


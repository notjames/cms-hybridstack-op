#!/bin/bash

export PATH=$PATH:$PWD/bin

# if a necessary argument specified on CLI at runtime, it takes precedence.
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

if ! su $OWNER_USER -c '
  export PATH=$PATH:/root/bin
  mkdir -p $HOME/.ssh && chmod 700 $HOME/.ssh
  cp -avp /root/.ssh/*.pem $HOME/.ssh

  for NODE_TYPE in master worker; do
    if ! bootstrap-nodes.sh -ct manager -nt $NODE_TYPE; then
      exit 55
    fi
  done'; then
    exit 50
fi

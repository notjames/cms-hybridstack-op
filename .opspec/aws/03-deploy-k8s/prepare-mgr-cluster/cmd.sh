#!/bin/bash

#set -x
export PATH=$PATH:/root/bin

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

master=$(bin/gen-aws-cmc-manifest.sh --get manager | jq -Mr '.manager_controllers[].address')
ssh_opts="-i $HOME/.ssh/${CLUSTER_ID}Key.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $OS_TYPE@$master"
tmp_config="/var/tmp/config.yaml"

chown -R "$OWNER_USER":"$OWNER_USER" /var

# pull it from master manager
# shellcheck disable=SC2086
su "$OWNER_USER" -c "scp $ssh_opts:.kube/config $tmp_config"

orig_server=$(yaml2json $tmp_config | jq -Mr '.clusters[0].cluster.server')
new_master=$(echo "$orig_server" | sed -r 's#(https?://).*(:[0-9]+)#'"\1$master\2"'#')

# alter the IP address from the internal AWS IP to the external facing IP address.
yaml2json $tmp_config | \
  jq --arg addr "$new_master" -Mr --slurp '.[].clusters[].cluster.server |= $addr | .[]' | \
  json2yaml - > "$HOME"/.kube/config

#cat "$HOME"/.kube/config
#sleep 2
# copy the working copy to a static location so future ops can get it.
cp "$HOME"/.kube/config /var/tmp/config

kubectl get nodes

# generate the cma-vmware manifest
bin/gen-aws-cmc-manifest.sh --get managed -c

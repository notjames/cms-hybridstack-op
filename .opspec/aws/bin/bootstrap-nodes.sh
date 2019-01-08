#!/bin/bash

#set -x

usage()
{
  echo """
  Usage: $0 --cluster-type|-ct <manager|managed> --node-type|-nt <master|worker>
            [--help|-h]

  """
}

own()
{
  [[ -z $1 ]] && return
  # shellcheck disable=SC2046
  chown -R $(stat -c '%u:%g' .) "$1"
}

copy_to_host()
{
  local things_to_copy host_ipaddr

  host_ipaddr="$1";shift
  things_to_copy="$*"

  # shellcheck disable=SC2086
  scp -i "$KEYFILE" $SSH_OPTIONS $things_to_copy "$USERNAME"@"$host_ipaddr":
}

get_ipaddr()
{
  curl -s http://bot.whatismyipaddress.com
}

gen_SANs_addrs()
{
  local my_ip sans addr

  my_ip=$(get_ipaddr)

  for addr in $my_ip $(gen-aws-cmc-manifest.sh --get manager | jq -Mr '.manager_controllers[0].address'); do
    sans+=$addr,
  done

  echo "$sans" | sed -re 's#,$##'
}

run_ssh_commands_master()
{
  local host_ipaddr

  host_ipaddr="$1"

  SANS=$(gen_SANs_addrs)

  # shellcheck disable=SC2086,SC2029
  if ! ssh -i "$KEYFILE" $SSH_OPTIONS $USERNAME@$host_ipaddr \
    "export EXTRA_SANS=$SANS;if [[ ! -f done ]]; then bash -x install_master.sh 2>&1 | tee startup.log; fi"; then
    echo >&2 "Remote commands failed. Please check logs."
    return 1
  fi

  # grab "kubeadm join string
  # shellcheck disable=SC2086
  scp -i "$KEYFILE" $SSH_OPTIONS "$USERNAME"@"$host_ipaddr":$JOIN_STRING .
}

run_ssh_commands_node()
{
  local host_ipaddr

  host_ipaddr="$1"

  # shellcheck disable=SC2086,SC2029
  if ! ssh -i "$KEYFILE" $SSH_OPTIONS $USERNAME@$host_ipaddr \
    "if [[ ! -f done ]]; then bash -x install_worker.sh $JOIN_STRING;fi"; then
    echo >&2 "Remote commands failed. Please check logs."
    return 1
  fi
}

manager_master_bootstrap()
{
  local host_ipaddr things_to_copy

  # obtain IP address of manager controller node
  host_ipaddr=$(bin/gen-aws-cmc-manifest.sh --get manager | jq -Mr '.manager_controllers[0].address')

  # scp common_functions to remote host
  things_to_copy=(bin/scripts/install_master.sh bin/scripts/common_functions.sh)
  copy_to_host "$host_ipaddr" "${things_to_copy[@]}"

  # if manager master, run master bits
  #   grab token string
  if ! run_ssh_commands_master "$host_ipaddr"; then
    return 1
  else
    ssh -i "$KEYFILE" $SSH_OPTIONS $USERNAME@$host_ipaddr "touch done"
  fi
}

manager_node_bootstrap()
{
  local host_ipaddr things_to_copy

  # obtain IP address of manager controller node
  host_ipaddr=$(bin/gen-aws-cmc-manifest.sh --get manager | jq -Mr '.manager_nodes[0].address')

  # scp common_functions to remote host
  things_to_copy=(bin/scripts/install_worker.sh bin/scripts/common_functions.sh $JOIN_STRING)
  copy_to_host "$host_ipaddr" "${things_to_copy[@]}"

  if ! run_ssh_commands_node "$host_ipaddr"; then
    return 1
  else
    ssh -i "$KEYFILE" $SSH_OPTIONS $USERNAME@$host_ipaddr "touch done"
  fi
}

main()
{
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --cluster-type|-ct)
        shift
        cluster_type=$1
      ;;
      --node-type|-nt)
        shift
        node_type=$1
      ;;
      --help|-h)
        usage
        return 0
      ;;
      *)
        echo >&2 "Unknown argument: $1"
        usage
        return 1
      ;;
    esac

    shift
  done

  if ! [[ $cluster_type =~ ^manage[rd]$ ]]; then
    echo >&2 "Invalid cluster type: '$cluster_type'. Must be 'manager' or 'managed'"
    usage
    return 1
  fi

  if ! [[ $node_type =~ ^(master|worker)$ ]]; then
    echo >&2 "Invalid node type: '$node_type'. Must be 'master' or 'worker'"
    usage
    return 1
  fi

  if [[ $cluster_type != "manager" ]]; then
    echo >&2 "This script should only be used to provision manager cluster machines."
    return 1
  fi

  if [[ $node_type == "master" ]]; then
    if manager_master_bootstrap; then
      return 0
    else
      echo >&2 "Bootstrap failed for manager master."
      return 1
    fi
  fi

  if ! manager_node_bootstrap; then
    return 1
  fi
}

# private key path
KEYFILE=$HOME/.ssh/${CLUSTER_ID}Key.pem

# join_string
JOIN_STRING="join_string.txt"

# ssh options
# turn off host checking and ignore the hosts file since this will be non-interactive.
SSH_OPTIONS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "

# username is the OS_TYPE
USERNAME=${USERNAME:-$OS_TYPE}

[[ -z "${CLUSTER_ID}" ]] && \
  {
    echo >&2 "CLUSTER_ID must be set."
    exit 20
  }

[[ -z "${USERNAME}" ]] && \
  {
    echo >&2 "USERNAME must be set."
    exit 21
  }

if ! main "$@"; then
  exit 50
fi

exit 0

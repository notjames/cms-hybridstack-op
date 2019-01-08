#!/bin/bash
# shellcheck disable=SC2046,SC2140

err()
{
  echo >&2 "$*"
}

say()
{
  echo "$*"
}

get_managed_nodes()
{
  local cluster_id

  cluster_id=$1

  [[ -z ${cluster_id} ]] && \
  {
    err "Usage: get_managed_nodes(cluster_id)"
    return 50
  }

  if [[ $TEXT == 1 ]]; then
    options='--output text'
  fi

  q="Reservations[].Instances[]."
  q+="{"
  q+="  name:    Tags[? Key == 'Name'].Value | [0],"
  q+="  address: PublicIpAddress"
  q+="} | [? contains(name,'$cluster_id')] | "
  q+="{"
  q+="  manager_controllers: [? contains(name, 'managed') && contains(name,'control')],"
  q+="  manager_nodes: [? contains(name, 'managed') && contains(name, 'work')]"
  q+="}"

  # shellcheck disable=SC2086
  aws ec2 describe-instances \
    --filter "Name=instance-state-name,Values='running'" \
    --query "$q" $options
}

get_manager_nodes()
{
  local cluster_id options

  options=""
  cluster_id=$1

  if [[ $TEXT == 1 ]]; then
    options='--output text'
  fi

  [[ -z ${cluster_id} ]] && \
  {
    err "Usage: get_manager_nodes(cluster_id)"
    return 50
  }

  q="Reservations[].Instances[]."
  q+="{"
  q+="  name:    Tags[? Key == 'Name'].Value | [0],"
  q+="  address: PublicIpAddress"
  q+="} | [? contains(name,'$cluster_id')] | "
  q+="{"
  q+="  manager_controllers: [? contains(name, 'manager') && contains(name,'control')],"
  q+="  manager_nodes: [? contains(name, 'manager') && contains(name, 'work')]"
  q+="}"

  # shellcheck disable=SC2086
  aws ec2 describe-instances \
    --filter "Name=instance-state-name,Values='running'" \
    --query "$q" $options
}

jo_control_planes()
{
  local nodes hostname

  nodes="$*"
  hostname=$(jq -Mr '.manager_controllers[].name' <<< "$nodes")

  jo username="${CLUSTER_USERNAME:-$OS_TYPE}" port=22 password="" \
    labels=$(jo -a $(jo name=Name value="$hostname"))
}

jo_worker_nodes()
{
  local nodes hostname

  nodes="$*"
  hostname=$(jq -Mr '.manager_nodes[].name' <<< "$nodes")

  jo username="${CLUSTER_USERNAME:-$OS_TYPE}" host="" port=22 password="" \
    labels=$(jo -a $(jo name=Name value="$hostname"))
}

create_worker_cluster_manifest()
{
  [[ -z "$*" ]] && \
    {
      echo >&2 "Requires nodes! Maybe none exist right now?"
      return 25
    }

  jo name="$CLUSTER_ID" \
     k8s_version="$KUBELET_VERSION" \
     high_availability=true \
     network_fabric=flannel \
     api_endpont="" \
     private_key="$CLUSTER_PRIVATE_KEY" \
     control_plane_nodes=$(jo_control_planes "$nodes") \
     worker_nodes=$(jo_worker_nodes "$nodes") | \
     sed 's/null/""/g' | json2yaml -
}

check_reqs()
{
  pass=0

  for req in "${REQS[@]}"; do
    if ! which "$req" >/dev/null 2>&1; then
      err "pre-requisite: $req does not exist or is not in your PATH. Please fix then re-run."
    else
      ((pass++))
    fi
  done

  [[ $pass -ne "${#REQS[*]}" ]] && return 15
  return 0
}

usage()
{
  echo """
Usage: $0 <--get <manager|managed>> [--create-manifest|-c] [--help|-h]

  """
}


[[ -z $CLUSTER_ID ]] && \
  {
    echo >&2 "\$CLUSTER_ID env variable must be set."
    exit 16
  }

#BASEDIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
#OUTDIR=${BASEDIR}/manifests
OUTDIR=/var/tmp/manifests
KUBELET_VERSION=${KUBELET_VERSION:-1.10.6}
REQS=(aws yaml2json json2yaml jo jq)
create_manifest=0
TEXT=0

create_cluster_base="$OUTDIR/create-$CLUSTER_ID"

[[ $# == 0 ]] && usage && exit 11

while [[ "$#" -gt 0 ]]; do
  arg=$1

  case $arg in
    --create-manifest|-c)
      create_manifest=1
      shift
    ;;
    --get|-g)
      shift
      what_to_get=$1
    ;;
    --text|-t)
      shift
      TEXT=1
    ;;
    --help|-h)
      usage
      exit 12
    ;;
    *) echo "Do not understand argument: $arg"
      usage
      exit 10
    ;;
  esac
  shift
done

if ! check_reqs; then
  exit 40
fi

case "$what_to_get" in
  manager) get_nodes=get_manager_nodes;;
  managed) get_nodes=get_managed_nodes;;
  *)
    echo >&2 "Do not understand how to get '$what_to_get'"
    usage
    exit 36
  ;;
esac

if nodes=$($get_nodes "$CLUSTER_ID") 2>/dev/null; then
  if [[ $create_manifest == 1 ]]; then
    mkdir -p "$OUTDIR" 2>/dev/null

    if [[ "$what_to_get" == "managed" ]]; then
      if [[ $(echo "$nodes" | jq '.manager_controllers | length') == 0 ]]; then
        echo >&2 "There are currently no managed nodes deployed. Cannot continue."
        exit 59
      fi

      if ! create_worker_cluster_manifest "$nodes" > "$create_cluster_base.yaml"; then
        exit 60
      else
        if [[ -s "$create_cluster_base.yaml" ]]; then
          yaml2json "$create_cluster_base.yaml" > "$create_cluster_base.json"
        fi
      fi
    else
      echo "Since manager clusters do not yet need a manifest, I don't know how to make one."
      exit 61
    fi
  else
    if [[ -z "$nodes" ]]; then
      echo "No nodes exist for $what_to_get"
    else
      echo "$nodes"
    fi
  fi
fi

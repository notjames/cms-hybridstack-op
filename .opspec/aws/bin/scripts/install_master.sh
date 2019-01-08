#!/usr/bin/env bash

# https://github.com/samsung-cnct/cluster-api-provider-ssh/blob/master/cloud/ssh/actuators/machine/setupconfigs_metadata.go
#KUBELET_VERSION={{ .Machine.Spec.Versions.Kubelet }}
#VERSION=v${KUBELET_VERSION}
#NAMESPACE={{ .Machine.ObjectMeta.Namespace }}
#MACHINE_NAME={{ .Machine.ObjectMeta.Name }}
#MACHINE=$NAMESPACE
#MACHINE+="/"
#MACHINE+=$MACHINE_NAME
#CONTROL_PLANE_VERSION={{ .Machine.Spec.Versions.ControlPlane }}
#CLUSTER_DNS_DOMAIN={{ .Cluster.Spec.ClusterNetwork.ServiceDomain }}
#POD_CIDR={{ .PodCIDR }}
#SERVICE_CIDR={{ .ServiceCIDR }}
#MASTER_IP={{ .MasterIP }}

# XXX this part needs work.
JOIN_STRING="$HOME/join_string.txt"
SERVICE_CIDR=${SERVICE_CIDR:-10.96.0.0/12}
POD_CIDR=${POD_CIDR:-10.24.0.0/16}
MASTER_IP=${MASTER_IP:-"$(curl -s http://169.254.169.254/2018-09-24/meta-data/public-ipv4)"}
CLUSTER_DNS_DOMAIN=${CLUSTER_DNS_DOMAIN:-cluster.local}
KUBELET_VERSION=${KUBELET_VERSION:-1.10.6}
EXTRA_SANS=${EXTRA_SANS}

export KUBELET_VERSION SERVICE_CIDR POD_CIDR \
       JOIN_STRING MASTER_IP CLUSTER_DNS_DOMAIN

# shellcheck disable=SC1091
if ! source common_functions.sh; then
  echo >&2 "Unable to source functions script."
  exit 15
fi

if ! install_docker; then
  echo >&2 "Unable to install docker."
  exit 16
fi

if ! install_k8s_w_yum; then
  echo >&2 "Unable to install yum."
  exit 17
fi

if ! configure_kubeadm; then
  echo >&2 "Unable to configure kubeadm."
  exit 18
fi

if ! run_kubeadm_master; then
  echo "EXTRA_SANS was: $EXTRA_SANS"
  echo >&2 "Unable to kubeadm init."
  exit 19
fi

if ! post_master_kubeadm_start; then
  echo >&2 "Unable to run post kubeadm steps."
  exit 20
fi

if ! install_components; then
  echo >&2 "Unable to install components."
  exit 21
fi

#!/usr/bin/env bash

JOIN_STRING="$HOME/join_string.txt"
SERVICE_CIDR=10.96.0.0/12
POD_CIDR=10.24.0.0/16
CLUSTER_DNS_DOMAIN=cluster.local
KUBELET_VERSION=1.10.6
OUTPUT_LOG="/var/log/startup.log"
HELM_VERSION="2.11.0"

export JOIN_STRING KUBELET_VERSION SERVICE_CIDR POD_CIDR \
       MASTER_IP CLUSTER_DNS_DOMAIN HELM_VERSION

if ! source common_functions.sh; then
  echo >&2 "Unable to source functions script."
  exit 15
fi

if ! install_docker | sudo tee -a $OUTPUT_LOG; then
  echo >&2 "Unable to install docker."
  exit 16
fi

if ! install_k8s_w_yum | sudo tee -a $OUTPUT_LOG; then
  echo >&2 "Unable to install yum."
  exit 17
fi

if ! configure_kubeadm | sudo tee -a $OUTPUT_LOG; then
  echo >&2 "Unable to configure kubeadm."
  exit 18
fi

if ! run_kubeadm_join | sudo tee -a $OUTPUT_LOG; then
  echo >&2 "Unable to kubeadm join."
  exit 19
fi

#if ! install_components | sudo tee -a $OUTPUT_LOG; then
#  echo >&2 "Unable to install components."
#  exit 20
#fi

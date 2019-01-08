install_docker()
{
  local docker_service dt
  docker_service='/usr/lib/systemd/system/docker.service'
  dt="$(date +%Y%m%dT%H:%M:%S)"

  sudo yum remove -y 'docker*'
  sudo yum install -y docker-1.13.1-75.git8633870.el7.centos

  if ! grep -q "native.cgroupdriver=systemd" "$docker_service"; then
    sed -r -i.bak-"$dt" 's#^(ExecStart=/usr/bin/dockerd)#\1 --exec-opt native.cgroupdriver=systemd \
                                                            --exec-opt runtime-cgroups=/systemd/system.slice \
                                                            --exec-opt kubelet-cgroups=/systemd/system.slice \
                                                            --exec-opt MountFlags=private#' \
         "$docker_service"
  else
    echo >&2 "WARNING: Looks like '$docker_service' was already updated. Skipping."
  fi

  cat <<E | sudo tee /etc/sysconfig/docker
DOCKER_OPTS="--iptables=false --ip-masq=false"
E

  sudo usermod -a -G docker "$USER"
  sudo chmod 640 /etc/sysconfig/docker

  if ! sudo systemctl enable --now docker;then
    echo >&2 "Unable to 'systemctl enable docker'. Quitting."
    return 1
  fi

  if ! sudo systemctl daemon-reload; then
    echo >&2 "Unable to reload systemctl daemon."
    return 1
  fi

  if sudo systemctl restart docker.service; then
    echo "docker is installed successfully."
  fi
}

prune_kubeadm_env()
{
  local kubeadmenv_dir kubeadmenv_file

  kubeadmenv_dir="/var/lib/kubelet"
  kubeadmenv_file="$kubeadmenv_dir/kubeadm-flags.env"

  # See https://samsung-cnct.atlassian.net/browse/CMS-391
  # If the file exists, grok it first (preserving current settings)
  if [[ -d $kubeadmenv_dir ]]; then
    if [[ -f "$kubeadmenv_file" ]]; then
      source "$kubeadmenv_file"

      # change the one we want to change
      if [[ -n $KUBELET_KUBEADM ]]; then
        if [[ $(echo "$KUBELET_KUBEADM_ARGS" | grep -c "--cgroup-driver=systemd") == 0 ]]; then
          if ! sudo sed -ri.bak-"$(date +%Y%m%dT%H%M%s)" 's/"(.*)"/"\1 --cgroup-driver-systemd"/' "$kubeadmenv_file"; then
            echo >&2 "FATAL: Unable to fix cgroupfs driver in $kubeadmenv_file"
            return 1
          fi
        else
          if ! echo "KUBELET_KUBEADM_ARGS=--cgroup-driver=systemd" | sudo tee "$kubeadmenv_file"; then
            echo >&2 "Unable to create $kubeadmenv_file!"
            return 1
          fi
        fi
      fi
    else
      cat << E | sudo tee "$kubeadmenv_file"
KUBELET_KUBEADM_ARGS=--cgroup-driver=systemd
E
      sudo chmod 644 "$kubeadmenv_file"
    fi
  fi
}

sysconfig_cgroupfs_fix()
{
  if grep -q "cgroup-driver=systemd" /etc/sysconfig/kubelet 2>/dev/null; then
    return 0
  else
    sed -ri.bak-"$(date +%Y%m%dT%H%M%s)" 's#^(KUBELET_EXTRA_ARGS=.*) #\1 --cgroup-driver=systemd#' /etc/sysconfig/kubelet
  fi
}

install_k8s_w_yum()
{
  if [[ -z $KUBELET_VERSION ]]; then
    echo >&2 "FATAL: \$KUBELET_VERSION is nil! Cannot continue."
    return 31
  fi

  cat << E | sudo tee /etc/yum.repos.d/kubernetes.repo
  [kubernetes]
  name=Kubernetes
  baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
  enabled=1
  gpgcheck=1
  repo_gpgcheck=1
  gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
E

  sudo sed -r -i 's#^\ +##g' /etc/yum.repos.d/kubernetes.repo

  # Set SELinux in permissive mode (effectively disabling it)
  sudo setenforce 0
  sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

  sudo yum install -y "kubelet-${KUBELET_VERSION}" \
                      "kubeadm-${KUBELET_VERSION}" \
                      "kubectl-${KUBELET_VERSION}" \
                      conntrack --disableexcludes=kubernetes
  #sysconfig_cgroupfs_fix
  configure_kubelet_systemd
  sudo systemctl enable kubelet && sudo systemctl start kubelet
}

prips()
{
  cidr=$1

  # range is bounded by network (-n) & broadcast (-b) addresses.
  # the following uses `read` with a here-statement to assign the output of
  # ipcalc -bn into two variables; $hi and $lo the output of which is cut and then
  # delimited by a ":". Read uses $IFS to automatically split on that delimiter.
  IFS=':' read -r hi lo <<< "$(ipcalc -bn "$cidr" | cut -f 2 -d = | sed -r 'N;s/\n/:/')"

  # similar to above only this is splitting on '.'.
  IFS='.' read -r a b c d <<< "$lo"
  IFS='.' read -r e f g h <<< "$hi"

  # kubeadm uses 10th IP as DNS server
  set +x
  eval "echo {$a..$e}.{$b..$f}.{$c..$g}.{$d..$h}" | awk '{print $11}'
  set -x
}

configure_kubelet_systemd()
{
  # configure kubelet
  cat << E | sudo tee /etc/systemd/system/kubelet.service.d/20-kubelet.conf
[Service]
Environment='KUBELET_DNS_ARGS=--cluster-dns="$(prips "$SERVICE_CIDR")" --cluster-domain=${CLUSTER_DNS_DOMAIN}'
E

  sudo chmod 644 /etc/systemd/system/kubelet.service.d/20-kubelet.conf
  sudo systemctl daemon-reload && sudo systemctl enable --now kubelet
}

configure_kubeadm()
{
  sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
  sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1
  sudo sysctl -p

  if [[ $(systemctl is-active firewalld.service) == "active" ]]; then
     sudo systemctl disable --now firewalld
  fi

  # configure kubeadm
  cat << E | sudo tee /etc/kubernetes/kubeadm_config.yaml
  ---
  apiVersion: kubeadm.k8s.io/v1alpha1
  kind: MasterConfiguration
  api:
    advertiseAddress: ${MASTER_IP}
    bindPort: 443
  etcd:
    local:
      dataDir: /var/lib/etcd
      image:
  kubernetesVersion: v${KUBELET_VERSION}
  token: ${TOKEN}
  kubeProxy:
    config:
      clusterCIDR: ${POD_CIDR}
  networking:
    dnsDomain: ${CLUSTER_DNS_DOMAIN}
    podSubnet: ${POD_CIDR}
    serviceSubnet: ${SERVICE_CIDR}
E

  # YAML is whitespace picky. So, need to fix kubeadm_config
  sudo sed -r -i 's#^[[:blank:]]{2}##' /etc/kubernetes/kubeadm_config.yaml

  # Create and set bridge-nf-call-iptables to 1 to pass the kubeadm preflight check.
  # Workaround was found here:
  # http://zeeshanali.com/sysadmin/fixed-sysctl-cannot-stat-procsysnetbridgebridge-nf-call-iptables/
  if [[ $(sudo lsmod | grep br_netfilter -c) == 0 ]];then
    sudo modprobe br_netfilter
  fi

  # Allowing swap may not be reliable:
  # https://github.com/kubernetes/kubernetes/issues/53533
  sudo swapoff -a
}

run_kubeadm_master()
{
  # EXTRA_SANS implicit here and is derived from caller's sourced environment variable.
  if ! sudo kubeadm init --pod-network-cidr 10.244.0.0/16 --apiserver-cert-extra-sans "$EXTRA_SANS"; then
    echo >&2 "Unable to start kubeadm."
    return 1
  fi

  # By default, use flannel for container network plugin, should make this configurable.
  sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml
}

run_kubeadm_join()
{
  if [[ -z $JOIN_STRING ]];  then
    echo >&2 "Cannot continue. The \$JOIN_STRING was nil."
    return 1
  else
    if line=$(< "$JOIN_STRING"); then
      MASTER_IP=$(echo "$line" | grep -Po '(\d{1,3}\.){3}\d{1,3}:\d+')
      TOKEN=$(echo "$line" | grep -Po '[\w\d]{6}\.[\w\d]+')
    else
      echo >&2 "Unable to read file '$JOIN_STRING'."
      exit  14
    fi
  fi

  sudo kubeadm join --token "${TOKEN}" "${MASTER_IP}" --ignore-preflight-errors=all --discovery-token-unsafe-skip-ca-verification
}

post_master_kubeadm_start()
{

  if [[ -z $JOIN_STRING ]];  then
    echo >&2 "Cannot continue. The \$JOIN_STRING was nil."
    return 1
  else
    while read -r line; do
      if echo "$line" | grep -q token;then
        echo "$line" > "$JOIN_STRING"
      fi
    done <<< "$(grep -Po 'kubeadm join.*--discovery.*' startup.log)"

    cd "$HOME" && mkdir "$HOME"/.kube && \
      sudo cp /etc/kubernetes/admin.conf "$HOME"/.kube/config && \
      sudo chown "$USER" "$HOME"/.kube/config
  fi
}

install_components()
{
  curl -sSL  'https://storage.googleapis.com/kubernetes-helm/helm-v2.12.0-rc.1-linux-amd64.tar.gz' | \
  tar -C /var/tmp -xvzf - linux-amd64/helm linux-amd64/tiller
  sudo mv /var/tmp/linux-amd64/* /usr/local/bin/

  if ! helm init; then
    echo >&2 "Helm failed to initialize. Helm installation needs to be verified."
    return 1
  fi

  curl -sSL https://dl.google.com/go/go1.11.2.linux-amd64.tar.gz | sudo tar -C /usr/local -xzf -
  sudo ln -s /usr/local/go/bin/go /usr/local/bin/go
  export GOROOT=/usr/local/go
  export GOPATH="$HOME"/go && mkdir -p "$GOPATH"/{bin,src,pkg}

  if ! go version; then
    echo >&2 "Go failed to properly install."
    return 1
  fi
}

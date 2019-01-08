#!/usr/bin/env sh

# initialize helm/tiller on cluster with cluster-admin account
if [ "$(kubectl get deploy -n kube-system --no-headers=true -o custom-columns=:metadata.name | grep tiller-deploy)" != "tiller-deploy" ]; then
    echo "initilizing tiller on cluster"
    # create tiller service account
    kubectl apply -f /tiller.yaml

    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller

    helm init --service-account tiller --wait
else
    echo "tiller already installed on cluster"
fi

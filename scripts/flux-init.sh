#!/usr/bin/env bash

set -e

usage() { echo "Usage: $0 [-r <repourl>] [-b <branch>] [-k <sealed-secrets-key-file>]" 1>&2; exit 1; }

while getopts r:k:b: option
do
case "${option}"
in
r) CUST_REPO=${OPTARG};;
b) CUST_BRANCH=${OPTARG};;
k) SS_MASTERKEY=${OPTARG};;
esac
done


if [[ ! -x "$(command -v kubectl)" ]]; then
    echo "kubectl not found"
    echo ">>> download the latest from here: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    exit 1
fi

if [[ ! -x "$(command -v helm)" ]]; then
    echo "helm not found"
    echo ">>> download the latest from here: https://github.com/helm/helm/releases"
    exit 1
fi

if [[ ! -x "$(command -v kubeseal)" ]]; then
    echo "kubeseal not found"
    echo ">>> download the latest from here: https://github.com/bitnami-labs/sealed-secrets/releases"
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_DEFAULT=$(git config --get remote.origin.url)
REPO_URL=${CUST_REPO:-$REPO_DEFAULT}
REPO_BRANCH_DEFAULT='master'
REPO_BRANCH=${CUST_BRANCH:-$REPO_BRANCH_DEFAULT}
REPO_PUBLIC=true

echo ">>> Cleaning up old roles and bindings"
if kubectl get clusterrole/fluxcd 2> /dev/null; 
then 
kubectl delete clusterrole/fluxcd;
fi

if kubectl get clusterrolebinding/fluxcd 2> /dev/null; 
then 
kubectl delete clusterrolebinding/fluxcd;
fi

echo ">>> Creating Flux Namespace"
kubectl apply -f https://raw.githubusercontent.com/ahanafy/cluster-base/master/base/fluxcd/namespace.yaml

helm repo add fluxcd https://charts.fluxcd.io

echo ">>> Installing Flux for ${REPO_URL}"
helm upgrade -i fluxcd fluxcd/flux --wait --cleanup-on-fail \
--set git.url=${REPO_URL} \
--set git.branch=${REPO_BRANCH} \
--set git.pollInterval=1m \
--set git.readonly=${REPO_PUBLIC} \
--set registry.pollInterval=1m \
--namespace fluxcd

echo ">>> Installing Helm Operator"
helm upgrade -i helm-operator fluxcd/helm-operator --wait --cleanup-on-fail \
--set git.ssh.secretName=fluxcd-git-deploy \
--set helm.versions=v3 \
-f https://raw.githubusercontent.com/ahanafy/cluster-base/master/base/fluxcd/repositories-configmap.yaml \
--namespace fluxcd

echo '>>> GitHub deploy key'
kubectl -n fluxcd logs deployment/fluxcd | grep identity.pub | cut -d '"' -f2

if ! [ -z ${SS_MASTERKEY+x} ]; 
then 
echo "applying '$SS_MASTERKEY'";
kubectl apply -f $SS_MASTERKEY;
fi
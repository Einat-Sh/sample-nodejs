#!/usr/bin/env bash
set -euo pipefail

DH_USER="einatsh"
GITOPS_BOOTSTRAP="https://raw.githubusercontent.com/Einat-Sh/sample-nodejs-gitops/main/bootstrap/root-application.yaml"
NS="sample-node-dev"
HOST="sample-node-example.local"

# start minikube cluster if it isn't already running
if ! minikube status >/dev/null 2>&1; then
  minikube start --driver=docker
fi
# enable ingress
minikube addons enable ingress
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s

# create ArgoCD namespace if it doesn't exist
if ! kubectl get ns argocd >/dev/null 2>&1; then
  kubectl create namespace argocd
  kubectl apply -n argocd --server-side \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi
# check rollout status for the ArgoCD server
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

# pull secret for DockerHub token (only if missing) 
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl -n "$NS" get secret dockerhub-pull >/dev/null 2>&1; then
  if [ -z "${DOCKERHUB_RO_TOKEN:-}" ]; then
    read -rsp "Docker Hub READ-ONLY token: " DOCKERHUB_RO_TOKEN; echo
  fi
  kubectl -n "$NS" create secret docker-registry dockerhub-pull \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username="$DH_USER" \
    --docker-password="$DOCKERHUB_RO_TOKEN"
fi

# bootstrap the root application from the gitops repository (safe to re-apply)
kubectl apply -n argocd -f "$GITOPS_BOOTSTRAP"

# port-forwards (restart cleanly)
pkill -f "port-forward svc/argocd-server" 2>/dev/null || true
pkill -f "port-forward svc/ingress-nginx-controller" 2>/dev/null || true
# forward argocd server to port 8081 and the ingress controller to 8080
kubectl -n argocd port-forward svc/argocd-server 8081:443 >/tmp/argocd-pf.log 2>&1 &
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80 >/tmp/ingress-pf.log 2>&1 &

echo "Waiting for Argo CD to create application '$NS'..."
for i in $(seq 1 60); do
  kubectl -n argocd get application "$NS" >/dev/null 2>&1 && break
  sleep 5
done

echo "Waiting for '$NS' to be Synced and Healthy"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/"$NS" --timeout=300s || true
kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/"$NS" --timeout=300s || true

# test applications creation - should show root and sample-node-dev
echo "Applications:"
kubectl -n argocd get applications
echo "Pods:"
kubectl -n $NS get pods

echo "Check Ingress:"
curl -H "Host: sample-node-example.local" http://localhost:8080/my-app && echo ""
curl -H "Host: sample-node-example.local" http://localhost:8080/about && echo ""
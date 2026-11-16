#!/usr/bin/env bash
set -e
# Trivy (image scanning) and Semgrep (SAST) for running the same checks locally
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin
pipx install semgrep
echo "Dev container ready. Start the cluster with: minikube start --driver=docker --cpus=3 --memory=6144"
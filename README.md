# DevOps Sample Node.js App

## Overview

A lightweight Node.js application. It features basic web endpoints, Prometheus metrics integration, and is designed for Kubernetes deployment and CI/CD pipeline demonstrations.

## Features

- Express.js web server
- Prometheus metrics integration
- Readiness and liveness probe endpoints
- Customizable port via environment variable

## Prerequisites

- Node.js (v24)
- Docker
- Trivy
- Minikube
- Helm
- Kubernetes kubectl
- Semgrep

The `.devcontainer/` folder installs all of these in a GitHub Codespace.

## Endpoints

| Path         | Exposed through the Ingress |
|--------------|-----------------------------|
| `/my-app`    | Yes                      |
| `/about`     | Yes                         |
| `/ready`     | No (kubelet probes the pod directly) |
| `/live`      | No (kubelet probes the pod directly) |
| `/metrics`   | No (meant to be scraped inside the cluster) |
| `/classified`| Demo route                      | No                          |

The Ingress lists only `/my-app` and `/about`, using `Exact` path matching.

## Docker
The application is containerized using Docker and Node.js 24 on Alpine Linux.

Build the image locally:
```bash
docker build -t sample-node:local .
```

Run the container in detached mode:
```bash
docker run -d --name sn -p 8080:8080 sample-node:local
```

Image test is done with Trivy, to check locally run:
```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed sample-node:local
```

### Image decisions

- Installs production dependencies only (`npm ci --omit=dev`).
- Runs as the unprivileged `node` user, not root.
- npm and npx are removed after installation - The app starts with
  `node app.js` and never needs npm at runtime, and the npm bundled in the
  base image carries packages (`undici`, `brace-expansion`) that fail the
  Trivy scan.
- Dependency fixes: Express was updated to 4.22.3, and `proxy-addr` is
  pinned to 2.0.8 through `overrides` in `package.json` to clear a critical Trivy
  finding.

## Kubernetes Deployment
The chart in `helm/sample-node` deploys the app as a Deployment, because
the app is stateless: any instance can serve any request, and there is no need
for persistent storage or a stable pod identity.

### Helm Lint
```bash
# default values (Ingress off)
helm lint helm/sample-node --strict

# CI values (Ingress on)
helm lint helm/sample-node --strict -f helm/sample-node/ci/test-values.yaml
```

### Resources
Memory and CPU limits were tested on the running docker container under load. CPU limit was left out 

To check run:
```bash
# Terminal 1:
docker run -d --name sn -p 8080:8080 --memory=256m --cpus=0.25 sample-node:local
docker stats sn

# Terminal 2:
seq 1 5000 | xargs -P 20 -I{} curl -s -o /dev/null localhost:8080/my-app

seq 1 500  | xargs -P 10 -I{} curl -s -o /dev/null localhost:8080/metrics
```

### Test On Minikube
After image build, start minikube in a doxker instance and load the image into it with:
```bash
minikube start --driver=docker
minikube image load sample-node:local
```

Deploy to kubernetees using helm:
```bash
helm install test-app helm/sample-node \
--set image.repository=sample-node \
--set image.tag=local \
--set image.pullPolicy=Never
```

Test the deployment with helm:
```bash
helm test test-app
```

Check Pods in case of issues:
```bash
kubectl get pods -A
kubectl describe pods
kubectl logs -l app.kubernetes.io/instance=test-app --tail=100
```
Clean up with `helm uninstall test-app` and `minikube stop` (in codespace, stopping the codespace instence is enough).

## Github Actions Pipeline
The project includes a GitHub Actions workflow that automates validation, security scanning, image building, and publishing.

If any of the tests fail, the pipeline fails and will not continue to run since each step is waiting for the competion of the step before it.

The pipeline consists of three main stages:
1. **Tests**: 
    - Helm lint - Validates the Helm chart using both default and CI-specific values
    - semgrep SAST - Perform SAST tests with semgrep scan. To check locally, run:
     ```bash
     semgrep scan \
        --config p/javascript \
        --config p/nodejs \
        --config p/owasp-top-ten \
        --error .
     ```

2. **Image** (waits for Tests to finish):
    - Build - builds the image from the Dockerfile with the current github commit tag for traceablility.
    - Test image - test the image with Trivy
    - Test helm deployment - test the helm deployment in a minikube continer and print failure logs in case of helm test errors.
    - Publish (only runs for pushes to main) - deploy the image to DockerHub private registry: einatsh/sample-node

3. **ArgoCD** Update (waits for Image to finish): 
Set and commit image tag for the gitops repo in the dev setup (`apps/sample-nodejs/dev/values.yaml`). Image tag is set to be the github commit SHA to.

The pipeline runs for both push and PR requests:
- on push to main - the pipeline runs fully
- on PR - the pipeline performs the tests, builds the image and test it but does not continue to publish and update argoCD.

### Pipeline Status
[![CI](https://github.com/Einat-Sh/sample-nodejs/actions/workflows/deploy.yaml/badge.svg?branch=main)](https://github.com/Einat-Sh/sample-nodejs/actions/workflows/deploy.yaml)

## ArgoCD
Deployment configuration lives in a separate GitOps repository
([`sample-nodejs-gitops`](https://github.com/Einat-Sh/sample-nodejs-gitops)), which ArgoCD watches.

 ### Manual running in codespace
 For testing use the `argocd_check.sh` script.

 The script:
 - Starts Minikube
 - Enables ingress
 - Creates/uses the ArgoCD namespace and check the rollout status of it
 - Pass the DockerHub RO token to ArgoCD if needed
 - Bootstrap the root application from the gitops repository
 - Port forwards the ArgoCD server to port 8081 and the app controller to port 8080
 - Check applications creation and pods creation
 - Check ingress with curl

To test run:
 ```bash
chmod +x .devcontainer/argocd_check.sh
./.devcontainer/argocd_check.sh
 ```

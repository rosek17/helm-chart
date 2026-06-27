# Cloud Rift Helm Chart

Umbrella Helm chart for deploying the Cloud Rift control plane on Kubernetes.

## Architecture

```
                  ┌──────────────────────────────────────┐
                  │               Ingress                │
                  │  /api/* /apidocs/*  /realms/*    /    │
                  └────┬────────┬──────────┬─────────┬────┘
                       │        │          │         │
              ┌────────▼──┐     │    ┌─────▼────┐  ┌─▼───────┐
              │   auth-   │     │    │ keycloak │  │ console │
              │  gateway  │     │    └─────┬────┘  └─────────┘
              │ :8080/8081│     │          │
              └─────┬─────┘     │     ┌────▼─────┐
                    │           │     │postgresql│
                    ▼           │     └──────────┘
              ┌──────────┐      │
              │ configdb │◄─────┘
              │ (mongo)  │
              └──────────┘
```

**Application components** (3): auth-gateway, cluster-manager, console

**Infrastructure subcharts** (2): configdb (MongoDB), keycloak (with PostgreSQL)

## Prerequisites

- Kubernetes cluster (v1.26+)
- Helm (v3.12+)
- `kubectl` configured for your cluster
- Access to the `ghcr.io/cloud-rift` container registry

## Quick Start

1. **Build chart dependencies:**

   ```bash
   helm dependency build rift/
   ```

   Or, from the repo root, resolve every local chart in dependency order:

   ```bash
   make deps
   ```

2. **Install with dev values:**

   ```bash
   helm install cloud-rift ./rift -f rift/dev-values.yaml
   ```

   `dev-values.yaml` supplies development defaults for all required passwords,
   so no extra `--set` flags are needed for a local install. For a production
   install, copy `values.yaml`, set the `""` password fields, and pass your file
   with `-f`.

3. **Verify deployment:**

   ```bash
   kubectl get pods
   ```

## Image Pull Secrets (Private Registry)

The application images (`ghcr.io/cloud-rift/auth-gateway`, `ghcr.io/cloud-rift/console`)
are published to a **private** registry. Rather than configuring an `imagePullSecret`
on every Deployment, attach a single pull secret to the **service account** the pods
run under — every pod scheduled with that account then inherits the credentials.

The chart does **not** create or manage this secret; you create it once in the
release namespace and map it onto the existing service account. The secret name
is taken from `global.imagePullSecret` (set to `ghcr-creds` in `dev-values.yaml`).
**If that value is left empty, skip this whole section** — no pull secret is
associated, which is the right choice when the images are public or pre-pulled.

1. **Create the registry secret** (type `kubernetes.io/dockerconfigjson`).
   Use a GitHub Personal Access Token with the `read:packages` scope. The secret
   name (`ghcr-creds` below) is the value you pass to the next step — change it if
   you prefer a different name.

   ```bash
   kubectl create secret docker-registry ghcr-creds \
     --namespace cloud-rift \
     --docker-server=ghcr.io \
     --docker-username=<github-username> \
     --docker-password=<github-pat> \
     --docker-email=<email>
   ```

2. **Map the secret onto the existing service account.** The Cloud Rift pods run
   under the namespace's `default` service account (the chart does not create a
   dedicated one). Patch it to reference the secret by name:

   ```bash
   kubectl patch serviceaccount default \
     --namespace cloud-rift \
     -p '{"imagePullSecrets":[{"name":"ghcr-creds"}]}'
   ```

   Substitute `ghcr-creds` with the secret name you chose in step 1.

3. **Roll the pods** so they pick up the credentials (service-account
   `imagePullSecrets` are applied only at pod creation time):

   ```bash
   kubectl rollout restart deployment -n cloud-rift
   ```

> **Note:** Do both steps **before** the first `helm install` to avoid an initial
> `ImagePullBackOff`. The infrastructure subcharts (configdb, keycloak) pull from
> public registries (`docker.io`, `quay.io`) and do not need this secret.

## Values Reference

### Global

| Parameter | Description | Default |
|---|---|---|
| `global.releaseTag` | Image tag for all components | `latest` |
| `global.imageRegistry` | Container registry | `ghcr.io/cloud-rift` |
| `global.imagePullPolicy` | Image pull policy for the ghcr.io app components | `Always` |
| `global.skipResourceConstraints` | Drop CPU/memory requests and limits | `false` |
| `global.tls.mode` | TLS mode: `self-signed`, `external`, `letsencrypt` | `self-signed` |
| `global.console.domain` | Domain for ingress and TLS certificate | `""` |
| `global.console.secretName` | Name of TLS secret | `""` (defaults to `tls-cert` internally) |
| `global.ingress.enabled` | Enable Ingress resource | `false` |
| `global.ingress.class` | Ingress class name | `nginx` |
| `global.ingress.annotations` | Additional ingress annotations | `{}` |
| `global.letsencrypt.email` | Email for Let's Encrypt (required if mode is `letsencrypt`) | `""` |
| `global.letsencrypt.issuer` | ClusterIssuer name | `letsencrypt-prod` |

### Infrastructure

| Parameter | Description | Default |
|---|---|---|
| `configdb.auth.rootPassword` | MongoDB root password | `""` (must set) |
| `configdb.persistence.size` | MongoDB storage size | `10Gi` |
| `keycloak.adminPassword` | Keycloak admin password | `""` (must set) |
| `keycloak.postgresql.password` | Keycloak PostgreSQL password | `""` (must set) |
| `keycloak.postgresql.persistence.size` | PostgreSQL storage size | `5Gi` |

### Application Components

Each application component supports:

| Parameter | Description |
|---|---|
| `<component>.fullnameOverride` | Override resource names (set for all components) |
| `<component>.image.repository` | Image repository name |
| `<component>.replicas` | Replica count |
| `<component>.resources` | CPU/memory requests and limits |

#### auth-gateway

| Parameter | Description | Default |
|---|---|---|
| `auth-gateway.config.mongoUri` | MongoDB connection string | `mongodb://configdb:27017/?replicaSet=rs0` |
| `auth-gateway.config.keycloakUrl` | Keycloak base URL | `http://keycloak:8080` |
| `auth-gateway.ports.external` | External (proxied) port | `8080` |
| `auth-gateway.ports.internal` | Internal management port | `8081` |

#### cluster-manager

Manages cluster lifecycle resources. Exposes a ClusterIP service on the HTTP API
port only; the auth-gateway forwards authenticated API requests to it (the gRPC
port is loopback-only and not published). Consumes MongoDB credentials from the
`configdb` secret, like auth-gateway.

| Parameter | Description | Default |
|---|---|---|
| `cluster-manager.config.mongoUri` | MongoDB connection string | `mongodb://configdb:27017/?replicaSet=rs0` |
| `cluster-manager.ports.api` | HTTP API port the gateway forwards to | `8080` |
| `cluster-manager.ports.grpc` | Native gRPC port (loopback only) | `8081` |
| `cluster-manager.config.catalog` | Operator-curated catalog (k8s versions, OS images, CNI, addons) | see `values.yaml` |

#### console

| Parameter | Description | Default |
|---|---|---|
| `console.service.type` | Service type (`ClusterIP` or `LoadBalancer`) | `ClusterIP` |
| `console.service.port` | HTTPS service port (when ingress is disabled) | `443` |
| `console.tls.secretName` | TLS secret mounted by the console proxy | `tls-cert` |
| `console.config.keycloakUrl` | Keycloak URL exposed to the frontend | `/` |
| `console.config.keycloakRealm` | Keycloak realm | `root` |
| `console.config.keycloakClientId` | Keycloak client ID | `controller` |
| `console.config.apiBaseUrl` | Base URL for API calls from the frontend | `/` |

## TLS Modes

The chart supports three TLS modes via `global.tls.mode`:

### self-signed (default)

Generates a self-signed certificate automatically. Suitable for development.

```yaml
global:
  tls:
    mode: self-signed
  console:
    domain: "localhost"
```

No additional configuration required.

### external

Use a TLS certificate you manage outside the chart. You must create the TLS secret before installing and reference it by name.

```yaml
global:
  tls:
    mode: external
  console:
    domain: "app.example.com"
    secretName: "my-tls-secret"   # must exist in the namespace
```

### letsencrypt

Automatically provisions a certificate via cert-manager. Requires [cert-manager](https://cert-manager.io/) installed in the cluster with a ClusterIssuer.

```yaml
global:
  tls:
    mode: letsencrypt
  console:
    domain: "app.example.com"
  letsencrypt:
    email: "admin@example.com"
    issuer: "letsencrypt-prod"    # must match your ClusterIssuer name
```

## Upgrade

```bash
helm upgrade cloud-rift ./rift -f rift/dev-values.yaml
```

To update chart dependencies after pulling new changes:

```bash
helm dependency update rift/
helm upgrade cloud-rift ./rift -f rift/dev-values.yaml
```

## Uninstall

```bash
helm uninstall cloud-rift
```

Note: PVCs created by stateful components (configdb, keycloak/postgresql) are **not** deleted automatically. To remove them:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=cloud-rift
```

## Troubleshooting

### Check pod status

```bash
kubectl get pods -l app.kubernetes.io/instance=cloud-rift
```

### View logs for a component

```bash
kubectl logs -l app.kubernetes.io/name=<component> --tail=100
```

### Port-forward to a service

```bash
# Console UI
kubectl port-forward svc/console 8443:443

# Auth Gateway API
kubectl port-forward svc/auth-gateway 8080:8080

# Keycloak admin console
kubectl port-forward svc/keycloak 8081:8080
```

### Common issues

| Symptom | Cause | Fix |
|---|---|---|
| Pods stuck in `Pending` | PVC not bound — no StorageClass or insufficient capacity | Check `kubectl get pvc` and ensure a default StorageClass exists |
| `ImagePullBackOff` | Missing registry credentials | Create the `ghcr-creds` secret and map it onto the default service account — see [Image Pull Secrets](#image-pull-secrets-private-registry) |
| TLS errors | Wrong TLS mode or missing secret | For `external` mode, verify `global.console.secretName` secret exists |
| Keycloak/Mongo pods crash on boot | Required password not set | Ensure `keycloak.adminPassword`, `keycloak.postgresql.password`, and `configdb.auth.rootPassword` are set (dev-values supplies defaults) |

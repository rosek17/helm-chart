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

**Application components** (2): auth-gateway, console

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

## Values Reference

### Global

| Parameter | Description | Default |
|---|---|---|
| `global.releaseTag` | Image tag for all components | `latest` |
| `global.imageRegistry` | Container registry | `ghcr.io/cloud-rift` |
| `global.imagePullPolicy` | Image pull policy | `IfNotPresent` |
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

#### console

| Parameter | Description | Default |
|---|---|---|
| `console.service.type` | Service type (`ClusterIP` or `LoadBalancer`) | `ClusterIP` |
| `console.service.port` | HTTPS service port (when ingress is disabled) | `443` |
| `console.tls.secretName` | TLS secret mounted by the console proxy | `tls-cert` |
| `console.config.keycloakUrl` | Keycloak URL exposed to the frontend | `/` |
| `console.config.keycloakRealm` | Keycloak realm | `root` |
| `console.config.keycloakClientId` | Keycloak client ID | `controller` |

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
| `ImagePullBackOff` | Missing registry credentials | Verify access to `ghcr.io/cloud-rift` and create an `imagePullSecret` if needed |
| TLS errors | Wrong TLS mode or missing secret | For `external` mode, verify `global.console.secretName` secret exists |
| Keycloak/Mongo pods crash on boot | Required password not set | Ensure `keycloak.adminPassword`, `keycloak.postgresql.password`, and `configdb.auth.rootPassword` are set (dev-values supplies defaults) |

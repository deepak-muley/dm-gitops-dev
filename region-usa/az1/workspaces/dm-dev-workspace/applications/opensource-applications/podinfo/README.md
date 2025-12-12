# Podinfo

Podinfo is a tiny web application made with Go that showcases best practices of running microservices in Kubernetes. It's commonly used for GitOps demonstrations and testing.

## Overview

- **Source**: [stefanprodan/podinfo](https://github.com/stefanprodan/podinfo)
- **Helm Chart**: OCI registry at `oci://ghcr.io/stefanprodan/charts`
- **Version**: `>=6.0.0`

## Components

| File | Description |
|------|-------------|
| `namespace.yaml` | Creates the `podinfo` namespace |
| `helmrepository.yaml` | OCI HelmRepository pointing to ghcr.io |
| `helmrelease.yaml` | HelmRelease configuration with values |
| `kustomization.yaml` | Kustomize resource list |

## Configuration

| Parameter | Value |
|-----------|-------|
| Namespace | `podinfo` |
| Service Type | ClusterIP |
| Service Port | 9898 |
| Replicas | 1 |
| CPU Request/Limit | 100m / 200m |
| Memory Request/Limit | 64Mi / 128Mi |
| UI Color | `#34577c` |

## Endpoints

| Path | Description |
|------|-------------|
| `/` | Web UI |
| `/version` | Version information |
| `/healthz` | Health check endpoint |
| `/readyz` | Readiness check endpoint |
| `/metrics` | Prometheus metrics |
| `/env` | Environment variables |
| `/headers` | Request headers |
| `/delay/{seconds}` | Delay response |
| `/status/{code}` | Return specific HTTP status code |

## Usage

### Access via Port Forward

```bash
kubectl port-forward -n podinfo svc/podinfo 9898:9898
```

Then open http://localhost:9898 in your browser.

### Check Health

```bash
kubectl get pods -n podinfo
kubectl get helmrelease -n podinfo
```

### View Logs

```bash
kubectl logs -n podinfo -l app.kubernetes.io/name=podinfo
```

## Customization

To customize the deployment, modify the `values` section in `helmrelease.yaml`:

```yaml
values:
  replicaCount: 2
  ui:
    color: "#your-color"
    message: "Your custom message"
  ingress:
    enabled: true
    hosts:
      - host: podinfo.example.com
        paths:
          - path: /
            pathType: Prefix
```

## References

- [Podinfo GitHub Repository](https://github.com/stefanprodan/podinfo)
- [Flux HelmRelease Documentation](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Flux OCI Repositories](https://fluxcd.io/flux/components/source/helmrepositories/#oci-repository)


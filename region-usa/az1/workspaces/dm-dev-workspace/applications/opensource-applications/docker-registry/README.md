# Docker Registry

A private container registry for storing and distributing Docker/OCI container images. This deployment uses the official Docker Registry image which implements the [OCI Distribution spec](https://github.com/opencontainers/distribution-spec).

## Overview

- **Source**: [Docker Hub - registry](https://hub.docker.com/_/registry)
- **GitHub**: [distribution/distribution](https://github.com/distribution/distribution)
- **Helm Chart**: OCI registry at `oci://registry-1.docker.io/bitnamicharts`
- **Image**: `registry:3` (latest v3.x)

## Components

| File | Description |
|------|-------------|
| `namespace.yaml` | Creates the `docker-registry` namespace |
| `helmrepository.yaml` | OCI HelmRepository pointing to Bitnami charts |
| `helmrelease.yaml` | HelmRelease configuration with values |
| `kustomization.yaml` | Kustomize resource list |

## Configuration

| Parameter | Value |
|-----------|-------|
| Namespace | `docker-registry` |
| Service Type | ClusterIP |
| Service Port | 5000 |
| Replicas | 1 |
| CPU Request/Limit | 100m / 500m |
| Memory Request/Limit | 128Mi / 512Mi |
| Persistence | Enabled (10Gi) |
| Security | Non-root, no privilege escalation |

## Usage

### Access via Port Forward

```bash
kubectl port-forward -n docker-registry svc/docker-registry 5000:5000
```

### Push Images to the Registry

```bash
# Tag your image for the local registry
docker tag myimage:latest localhost:5000/myimage:latest

# Push to the registry
docker push localhost:5000/myimage:latest
```

### Pull Images from the Registry

```bash
docker pull localhost:5000/myimage:latest
```

### List Images in Registry

```bash
# List all repositories
curl http://localhost:5000/v2/_catalog

# List tags for a specific image
curl http://localhost:5000/v2/myimage/tags/list
```

### Check Health

```bash
kubectl get pods -n docker-registry
kubectl get helmrelease -n docker-registry
kubectl get pvc -n docker-registry
```

### View Logs

```bash
kubectl logs -n docker-registry -l app.kubernetes.io/name=docker-registry
```

## Customization

To customize the deployment, modify the `values` section in `helmrelease.yaml`:

```yaml
values:
  # Increase storage
  persistence:
    size: 50Gi
    storageClass: "fast-storage"

  # Enable ingress
  ingress:
    enabled: true
    hostname: registry.example.com
    tls: true

  # Scale replicas
  replicaCount: 2

  # Configure garbage collection
  extraEnvVars:
    - name: REGISTRY_STORAGE_DELETE_ENABLED
      value: "true"
```

## Storage

The registry uses persistent storage to retain images across pod restarts. By default:

- **Size**: 10Gi
- **Access Mode**: ReadWriteOnce
- **Storage Class**: Default cluster storage class

## Security Considerations

1. **Non-root execution**: Container runs as non-root user
2. **No privilege escalation**: Prevented by security context
3. **Authentication**: Not enabled by default - consider adding for production
4. **TLS**: Recommended for production use via Ingress with TLS

### Adding Basic Authentication

For production, consider adding authentication:

```yaml
values:
  auth:
    htpasswd:
      enabled: true
      username: "admin"
      password: "secure-password"
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /v2/` | API version check |
| `GET /v2/_catalog` | List repositories |
| `GET /v2/<name>/tags/list` | List tags for an image |
| `GET /v2/<name>/manifests/<ref>` | Get image manifest |
| `DELETE /v2/<name>/manifests/<ref>` | Delete image (if enabled) |

## References

- [Docker Registry Documentation](https://distribution.github.io/distribution/)
- [Docker Hub - registry](https://hub.docker.com/_/registry)
- [OCI Distribution Spec](https://github.com/opencontainers/distribution-spec)
- [Flux HelmRelease Documentation](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Bitnami Docker Registry Chart](https://github.com/bitnami/charts/tree/main/bitnami/docker-registry)


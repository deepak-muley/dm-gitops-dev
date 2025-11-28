 <!-- Apply this first -->
 <pre>
kubectl apply -f -  <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: dept-1-tenant-namespace
spec: {}
status: {}
EOF
</pre>

<pre>
kubectl apply -f -  <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: dm-gitops-dev
  namespace: dept-1-tenant-namespace
spec:
  interval: 5s
  ref:
    branch: main
  timeout: 20s
  url: https://github.com/deepak-muley/dm-gitops-dev.git
EOF
</pre>

<pre>
kubectl apply -f -  <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dm-gitops-dev-demo
  namespace: dept-1-tenant-namespace
spec:
  interval: 5s
  path: ./
  prune: true
  sourceRef:
   kind: GitRepository
   name: dm-gitops-dev
   namespace: dept-1-tenant-namespace
EOF
</pre>
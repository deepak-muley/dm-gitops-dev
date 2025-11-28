 <!-- Apply this first -->
kubectl apply -f -  <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: dept-1-tenant-namespace
spec: {}
status: {}
EOF

kubectl apply -f -  <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: dm-gitops-dev
  namespace: kommander
spec:
  interval: 5s
  ref:
    branch: main
  timeout: 20s
  url: https://github.com/deepak-muley/dm-gitops-dev.git
EOF

kubectl apply -f -  <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dm-gitops-dev-demo
  namespace: kommander
spec:
  interval: 5s
  path: ./
  prune: true
  sourceRef:
   kind: GitRepository
   name: gitops-demo
   namespace: kommander
EOF
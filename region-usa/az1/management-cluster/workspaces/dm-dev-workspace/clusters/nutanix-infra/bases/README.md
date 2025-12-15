<!-- https://fluxcd.io/flux/guides/sealed-secrets/ -->

brew install flux
brew install kubeseal

flux create source helm sealed-secrets \
--interval=1h \
--url=https://bitnami-labs.github.io/sealed-secrets \
--namespace=sealed-secrets-system \
--export > sealed-secrets-helmrepository.yaml

flux create helmrelease sealed-secrets \
--interval=1h \
--release-name=sealed-secrets-controller \
--target-namespace=sealed-secrets-system \
--source=HelmRepository/sealed-secrets \
--chart=sealed-secrets \
--chart-version=">=1.15.0-0" \
--crds=CreateReplace \
--export > sealed-secret-helmrelease.yaml

<!-- generate local public key to checkin -->
 kubeseal --fetch-cert \
 --controller-name=sealed-secrets-controller \
 --controller-namespace=sealed-secrets-system \
 > sealed-secrets-public-key.pem

 kubeseal --format=yaml --cert=./sealed-secrets-public-key.pem < dm-nkp-workload-1-secrets.yaml > dm-nkp-workload-1-selaed-secrets.yaml
 kubeseal --format=yaml --cert=./sealed-secrets-public-key.pem < dm-nkp-workload-2-secrets.yaml > dm-nkp-workload-2-selaed-secrets.yaml

<!-- Private key is already deployed in the management cluster -->
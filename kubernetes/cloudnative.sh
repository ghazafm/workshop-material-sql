helm repo add cnpg https://cloudnative-pg.github.io/charts
helm upgrade --install cnpg \
  --namespace workshop-ghaza \
  --create-namespace \
  cnpg/cloudnative-pg
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm upgrade --install cnpg \
  --namespace workshop \
  --create-namespace \
  cnpg/cloudnative-pg
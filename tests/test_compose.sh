#!/usr/bin/env bash
set -euo pipefail

compose_config=$(docker compose config)

grep -q '^  nginx:$' <<<"$compose_config"
grep -q 'nginx:1.27-alpine' <<<"$compose_config"

if grep -A10 '^  http-server-projeto-korp:$' <<<"$compose_config" | grep -q '^    ports:'; then
  echo 'A aplicação não deve publicar a porta 8080 no host' >&2
  exit 1
fi

echo 'Compose contém NGINX na borda e mantém a porta da aplicação interna.'

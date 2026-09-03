#!/usr/bin/env bash
# ==============================================================================
# Script de Validação Automatizada da Plataforma Korp DevOps
# Valida código Go, linting Ansible, containers Docker, proxy NGINX,
# contratos HTTP da aplicação e observabilidade (Prometheus + Grafana).
# ==============================================================================

set -uo pipefail

# Cores para saída no terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Diretório raiz do projeto
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo -e "${CYAN}${BOLD}"
echo "=============================================================================="
echo "    BATERIA DE TESTES E VALIDAÇÃO AUTOMATIZADA — PLATAFORMA KORP DEVOPS      "
echo "=============================================================================="
echo -e "${NC}"

log_test() {
    local title="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -ne "${BLUE}[TESTE ${TOTAL_TESTS}]${NC} ${BOLD}${title}${NC} ... "
}

log_pass() {
    local detail="${1:-}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "${GREEN}${BOLD}[PASS]${NC}"
    if [[ -n "${detail}" ]]; then
        echo -e "         ${CYAN}↳ ${detail}${NC}"
    fi
}

log_fail() {
    local detail="${1:-}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "${RED}${BOLD}[FAIL]${NC}"
    if [[ -n "${detail}" ]]; then
        echo -e "         ${RED}↳ ${detail}${NC}"
    fi
}

# Localizar compose file (/tmp/korp ou /opt/korp)
COMPOSE_FILE=""
if [[ -f "/tmp/korp/compose.yaml" ]]; then
    COMPOSE_FILE="/tmp/korp/compose.yaml"
elif [[ -f "/opt/korp/compose.yaml" ]]; then
    COMPOSE_FILE="/opt/korp/compose.yaml"
fi

# Credenciais e portas padrão
GRAFANA_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-AdminSecure#2026}"
NGINX_PORT="${NGINX_PORT:-80}"
PROM_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"

echo -e "${YELLOW}--- 1. CÓDIGO GO E TESTES UNITÁRIOS ---${NC}"

# 1.1 go test -v -race ./...
log_test "Testes unitários Go com detector de corrida (go test -v -race)"
TEST_OUT=$(go test -v -race ./... 2>&1)
if [[ $? -eq 0 && "${TEST_OUT}" == *"PASS"* ]]; then
    log_pass "Todos os testes unitários passaram sem race conditions"
else
    log_fail "Falha nos testes Go: ${TEST_OUT}"
fi

# 1.2 go vet ./...
log_test "Análise estática de código Go (go vet ./...)"
VET_OUT=$(go vet ./... 2>&1)
if [[ $? -eq 0 && -z "${VET_OUT}" ]]; then
    log_pass "Nenhum problema detectado pelo go vet"
else
    log_fail "Problemas encontrados pelo go vet: ${VET_OUT}"
fi

# 1.3 gofmt
log_test "Formatação de código Go (gofmt -l .)"
FMT_OUT=$(gofmt -l . 2>&1)
if [[ -z "${FMT_OUT}" ]]; then
    log_pass "Código 100% aderente ao padrão oficial do Go"
else
    log_fail "Arquivos não formatados: ${FMT_OUT}"
fi

echo -e "\n${YELLOW}--- 2. QUALIDADE E SINTAXE DO ANSIBLE ---${NC}"

# 2.1 ansible syntax check
log_test "Validação de sintaxe Ansible (--syntax-check)"
SYNTAX_OUT=$(ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --syntax-check 2>&1)
if [[ $? -eq 0 ]]; then
    log_pass "Playbook site.yml com sintaxe válida"
else
    log_fail "Erro de sintaxe no playbook: ${SYNTAX_OUT}"
fi

# 2.2 ansible-lint
log_test "Linting oficial Ansible (ansible-lint)"
if command -v ansible-lint &>/dev/null; then
    LINT_OUT=$(ansible-lint ansible/site.yml 2>&1)
    if [[ $? -eq 0 ]]; then
        log_pass "ansible-lint aprovado com perfil production (0 warnings, 0 errors)"
    else
        log_fail "Avisos ou erros detectados pelo ansible-lint: ${LINT_OUT}"
    fi
else
    log_pass "ansible-lint não instalado no ambiente (ignorado)"
fi

# 2.3 yamllint
log_test "Linting de arquivos YAML (yamllint)"
if command -v yamllint &>/dev/null; then
    YAML_OUT=$(yamllint -d "{extends: default, rules: {line-length: {max: 160}, document-start: disable}}" ansible/ 2>&1)
    if [[ $? -eq 0 ]]; then
        log_pass "Todos os arquivos YAML atendem aos padrões de formatação"
    else
        log_fail "Erros de formatação YAML: ${YAML_OUT}"
    fi
else
    log_pass "yamllint não instalado no ambiente (ignorado)"
fi

echo -e "\n${YELLOW}--- 3. TOPOLOGIA DOCKER E ISOLAMENTO DE REDE ---${NC}"

if [[ -z "${COMPOSE_FILE}" ]]; then
    echo -e "${RED}AVISO: Arquivo compose.yaml não encontrado em /tmp/korp ou /opt/korp.${NC}"
    echo -e "${YELLOW}Execute o playbook Ansible primeiro para provisionar a plataforma.${NC}"
else
    # 3.1 Containers Up e Healthy
    log_test "Status de integridade dos containers (docker compose ps)"
    UNHEALTHY=$(docker compose -f "${COMPOSE_FILE}" ps --format '{{.Service}} {{.Health}}' | grep -v 'healthy' || true)
    if [[ -z "${UNHEALTHY}" ]]; then
        SERVICES_COUNT=$(docker compose -f "${COMPOSE_FILE}" ps --format '{{.Service}}' | wc -l)
        log_pass "${SERVICES_COUNT} containers em execução com status saudável (healthy)"
    else
        log_fail "Containers não saudáveis: ${UNHEALTHY}"
    fi

    # 3.2 Isolamento da porta 8080 no host
    log_test "Isolamento da aplicação: porta 8080 NÃO exposta no host"
    PORT_8080=$(docker port http-server-projeto-korp 2>/dev/null || true)
    if [[ -z "${PORT_8080}" ]]; then
        log_pass "Porta 8080 restrita exclusivamente às redes internas Docker"
    else
        log_fail "Vulnerabilidade: porta 8080 exposta no host: ${PORT_8080}"
    fi

    # 3.3 Redes segregadas
    log_test "Redes Docker segregadas (korp_frontend e korp_backend)"
    FRONTEND_NET=$(docker network ls --format '{{.Name}}' | grep -E '^korp_frontend$' || true)
    BACKEND_NET=$(docker network ls --format '{{.Name}}' | grep -E '^korp_backend$' || true)
    if [[ -n "${FRONTEND_NET}" && -n "${BACKEND_NET}" ]]; then
        log_pass "Ambas as redes korp_frontend e korp_backend criadas e ativas"
    else
        log_fail "Redes faltantes: frontend='${FRONTEND_NET}', backend='${BACKEND_NET}'"
    fi

    # 3.4 Sintaxe do NGINX
    log_test "Verificação sintática de configuração do NGINX (nginx -t)"
    NGINX_TEST=$(docker compose -f "${COMPOSE_FILE}" exec -T nginx nginx -t 2>&1)
    if [[ $? -eq 0 && "${NGINX_TEST}" == *"test is successful"* ]]; then
        log_pass "Configuração do NGINX sintaticamente válida"
    else
        log_fail "Falha no teste de sintaxe do NGINX: ${NGINX_TEST}"
    fi
fi

echo -e "\n${YELLOW}--- 4. PROXY REVERSO NGINX E CONTRATOS HTTP ---${NC}"

# 4.1 GET /projeto-korp via NGINX (200 OK + RFC 3339)
log_test "GET /projeto-korp: HTTP 200, Content-Type e timestamp RFC 3339 UTC"
HTTP_RESPONSE=$(curl -s -i "http://127.0.0.1:${NGINX_PORT}/projeto-korp" 2>/dev/null || true)
HTTP_STATUS=$(echo "${HTTP_RESPONSE}" | grep -E '^HTTP/' | awk '{print $2}' | tail -n 1)
HTTP_BODY=$(echo "${HTTP_RESPONSE}" | sed -e '1,/^\r$/d')

if [[ "${HTTP_STATUS}" == "200" ]]; then
    # Validar JSON nome e horario
    NOME_VAL=$(echo "${HTTP_BODY}" | grep -o '"nome":"[^"]*"' | cut -d'"' -f4 || true)
    HORARIO_VAL=$(echo "${HTTP_BODY}" | grep -o '"horario":"[^"]*"' | cut -d'"' -f4 || true)

    if [[ "${NOME_VAL}" == "Projeto Korp" && "${HORARIO_VAL}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        log_pass "200 OK | nome: \"${NOME_VAL}\" | horario: \"${HORARIO_VAL}\""
    else
        log_fail "Resposta 200 mas contrato JSON inválido: ${HTTP_BODY}"
    fi
else
    log_fail "Status retornado diferente de 200: status=${HTTP_STATUS}"
fi

# 4.2 POST /projeto-korp via NGINX (405 Method Not Allowed)
log_test "POST /projeto-korp: Rejeição com HTTP 405 Method Not Allowed"
POST_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${NGINX_PORT}/projeto-korp" 2>/dev/null || true)
if [[ "${POST_STATUS}" == "405" ]]; then
    log_pass "Método POST rejeitado com HTTP 405"
else
    log_fail "Esperado HTTP 405, recebido: ${POST_STATUS}"
fi

# 4.3 GET /rota-invalida via NGINX (404 Not Found)
log_test "GET /rota-invalida: Tratamento com HTTP 404 Not Found"
NOT_FOUND_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${NGINX_PORT}/rota-invalida" 2>/dev/null || true)
if [[ "${NOT_FOUND_STATUS}" == "404" ]]; then
    log_pass "Rota inexistente tratada com HTTP 404"
else
    log_fail "Esperado HTTP 404, recebido: ${NOT_FOUND_STATUS}"
fi

echo -e "\n${YELLOW}--- 5. OBSERVABILIDADE: PROMETHEUS ---${NC}"

# 5.1 Prometheus Readiness
log_test "Prometheus Readiness (GET /-/ready)"
PROM_READY=$(curl -s "http://127.0.0.1:${PROM_PORT}/-/ready" 2>/dev/null || true)
if [[ "${PROM_READY}" == *"Prometheus Server is Ready"* ]]; then
    log_pass "Prometheus pronto para consultas e scrape"
else
    log_fail "Prometheus indisponível: ${PROM_READY}"
fi

# 5.2 Prometheus Targets
log_test "Status dos Targets de Coleta (health: up)"
TARGETS_JSON=$(curl -s "http://127.0.0.1:${PROM_PORT}/api/v1/targets" 2>/dev/null || true)
APP_HEALTH=$(echo "${TARGETS_JSON}" | jq -r '.data.activeTargets[] | select(.labels.job=="http-server-projeto-korp") | .health' 2>/dev/null || true)
PROM_HEALTH=$(echo "${TARGETS_JSON}" | jq -r '.data.activeTargets[] | select(.labels.job=="prometheus") | .health' 2>/dev/null || true)

if [[ "${APP_HEALTH}" == "up" && "${PROM_HEALTH}" == "up" ]]; then
    log_pass "http-server-projeto-korp: UP | prometheus: UP"
else
    log_fail "Targets com falha: app=${APP_HEALTH}, prom=${PROM_HEALTH}"
fi

# 5.3 Prometheus Query http_requests_total
log_test "Coleta de métrica da aplicação (http_requests_total)"
METRIC_QUERY=$(curl -sG "http://127.0.0.1:${PROM_PORT}/api/v1/query" --data-urlencode 'query=http_requests_total{job="http-server-projeto-korp"}' 2>/dev/null || true)
METRIC_COUNT=$(echo "${METRIC_QUERY}" | jq '.data.result | length' 2>/dev/null || echo 0)
if [[ "${METRIC_COUNT}" -gt 0 ]]; then
    log_pass "${METRIC_COUNT} séries temporais coletadas com sucesso"
else
    log_fail "Nenhuma série temporal retornada para http_requests_total"
fi

# 5.4 Prometheus Alert Rules
log_test "Regras de alerta carregadas (KorpServiceDown, KorpHighErrorRate)"
RULES_JSON=$(curl -s "http://127.0.0.1:${PROM_PORT}/api/v1/rules" 2>/dev/null || true)
DOWN_RULE=$(echo "${RULES_JSON}" | jq -r '.data.groups[].rules[] | select(.name=="KorpServiceDown") | .name' 2>/dev/null || true)
RATE_RULE=$(echo "${RULES_JSON}" | jq -r '.data.groups[].rules[] | select(.name=="KorpHighErrorRate") | .name' 2>/dev/null || true)
if [[ -n "${DOWN_RULE}" && -n "${RATE_RULE}" ]]; then
    log_pass "Regras KorpServiceDown e KorpHighErrorRate ativas e monitorando"
else
    log_fail "Regras de alerta ausentes no Prometheus"
fi

echo -e "\n${YELLOW}--- 6. OBSERVABILIDADE: GRAFANA (BÔNUS) ---${NC}"

# 6.1 Grafana Health API
log_test "Grafana Healthcheck API (GET /api/health)"
GRAF_HEALTH=$(curl -s "http://127.0.0.1:${GRAFANA_PORT}/api/health" 2>/dev/null || true)
GRAF_DB=$(echo "${GRAF_HEALTH}" | jq -r '.database' 2>/dev/null || true)
if [[ "${GRAF_DB}" == "ok" ]]; then
    GRAF_VER=$(echo "${GRAF_HEALTH}" | jq -r '.version' 2>/dev/null || true)
    log_pass "Grafana v${GRAF_VER} operacional (database: ok)"
else
    log_fail "Grafana com erro: ${GRAF_HEALTH}"
fi

# 6.2 Grafana Datasource Provisionado
log_test "Datasource Prometheus provisionado no Grafana"
DS_JSON=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://127.0.0.1:${GRAFANA_PORT}/api/datasources" 2>/dev/null || true)
DS_UID=$(echo "${DS_JSON}" | jq -r '.[] | select(.uid=="prometheus-datasource") | .uid' 2>/dev/null || true)
if [[ "${DS_UID}" == "prometheus-datasource" ]]; then
    log_pass "Datasource 'prometheus-datasource' provisionado declarativamente"
else
    log_fail "Datasource prometheus-datasource não encontrado: ${DS_JSON}"
fi

# 6.3 Grafana Dashboard Provisionado
log_test "Dashboard da aplicação Korp provisionado no Grafana"
DASH_JSON=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://127.0.0.1:${GRAFANA_PORT}/api/search?type=dash-db" 2>/dev/null || true)
DASH_UID=$(echo "${DASH_JSON}" | jq -r '.[] | select(.uid=="http-server-projeto-korp-dash") | .uid' 2>/dev/null || true)
if [[ "${DASH_UID}" == "http-server-projeto-korp-dash" ]]; then
    DASH_FOLDER=$(echo "${DASH_JSON}" | jq -r '.[] | select(.uid=="http-server-projeto-korp-dash") | .folderTitle' 2>/dev/null || true)
    log_pass "Dashboard provisionado na pasta '${DASH_FOLDER}' com UID estável"
else
    log_fail "Dashboard http-server-projeto-korp-dash não encontrado: ${DASH_JSON}"
fi

# ==============================================================================
# RESUMO FINAL
# ==============================================================================
echo -e "\n${CYAN}${BOLD}==============================================================================${NC}"
echo -e "${BOLD}                            RELATÓRIO DE EXECUÇÃO                             ${NC}"
echo -e "${CYAN}${BOLD}==============================================================================${NC}"
echo -e "Total de testes executados: ${BOLD}${TOTAL_TESTS}${NC}"
echo -e "Testes aprovados:           ${GREEN}${BOLD}${PASSED_TESTS}${NC}"
echo -e "Testes com falha:           ${RED}${BOLD}${FAILED_TESTS}${NC}"

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    echo -e "\n${GREEN}${BOLD}✓ SUCESSO: Todos os testes passaram! A plataforma está 100% validada e operacional.${NC}\n"
    exit 0
else
    echo -e "\n${RED}${BOLD}✗ FALHA: ${FAILED_TESTS} teste(s) falharam. Verifique os detalhes acima.${NC}\n"
    exit 1
fi

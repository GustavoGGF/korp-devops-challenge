#!/usr/bin/env bash
# ==============================================================================
# Suíte de Testes Automatizada: Validação de Handlers Ansible (NGINX e Prometheus)
# Baseado no plano-correcao-handlers-ansible.md
# ==============================================================================
set -Eeuo pipefail

# Paleta de Cores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${BASE_DIR}/ansible/inventory/hosts.ini"
TEST_PLAYBOOK="${BASE_DIR}/tests/test_handlers.yml"
COMPOSE_FILE="/opt/korp/compose.yaml"

NGINX_CONF_PATH="/opt/korp/nginx/conf.d/http-server-projeto-korp.conf"
PROM_RULES_PATH="/opt/korp/prometheus/rules/alerts.yml"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

log_header() {
    echo -e "\n${BLUE}${BOLD}==============================================================================${NC}"
    echo -e "${BOLD} $1 ${NC}"
    echo -e "${BLUE}${BOLD}==============================================================================${NC}"
}

log_test() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "\n${CYAN}[TESTE ${TOTAL_TESTS}]${NC} ${BOLD}$1${NC}"
}

log_pass() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "  ${GREEN}✓ PASSOU:${NC} $1"
}

log_fail() {
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "  ${RED}✗ FALHOU:${NC} $1"
}

# Helpers para manipular arquivos em /opt/korp de forma segura e não interativa via Docker
docker_read_file() {
    local target="$1"
    docker run --rm -v /opt/korp:/opt/korp alpine cat "${target}"
}

docker_write_file() {
    local target="$1"
    local content="$2"
    docker run --rm -i -v /opt/korp:/opt/korp alpine sh -c "cat > '${target}'" <<< "${content}"
}

# Backup em memória para garantir integridade e restauração
ORIGINAL_NGINX_CONF=$(docker_read_file "${NGINX_CONF_PATH}")
ORIGINAL_PROM_RULES=$(docker_read_file "${PROM_RULES_PATH}")

cleanup() {
    echo -e "\n${YELLOW}Executando rotina de restauração e cleanup...${NC}"
    if [[ -n "${ORIGINAL_NGINX_CONF:-}" ]]; then
        docker_write_file "${NGINX_CONF_PATH}" "${ORIGINAL_NGINX_CONF}" 2>/dev/null || true
    fi

    if [[ -n "${ORIGINAL_PROM_RULES:-}" ]]; then
        docker_write_file "${PROM_RULES_PATH}" "${ORIGINAL_PROM_RULES}" 2>/dev/null || true
    fi

    # Garantir que containers estejam iniciados
    docker compose -f "${COMPOSE_FILE}" start nginx >/dev/null 2>&1 || true
    docker compose -f "${COMPOSE_FILE}" start prometheus >/dev/null 2>&1 || true
}

trap cleanup EXIT

log_header "INÍCIO DA VALIDAÇÃO DOS HANDLERS ANSIBLE"

# Garantir estado inicial saudável
echo -e "${YELLOW}Verificando prontidão da infraestrutura base...${NC}"
docker compose -f "${COMPOSE_FILE}" up -d >/dev/null 2>&1

# ------------------------------------------------------------------------------
# 1. Configuração válida deve permitir reload bem-sucedido
# ------------------------------------------------------------------------------
log_test "Cenário 1.1: Reload do NGINX com configuração válida deve ter sucesso (exit code 0)"
set +e
OUTPUT_NGINX_OK=$(ansible-playbook -i "${INVENTORY}" "${TEST_PLAYBOOK}" -e "test_target=nginx_reload" 2>&1)
STATUS_NGINX_OK=$?
set -e

if [[ ${STATUS_NGINX_OK} -eq 0 && "${OUTPUT_NGINX_OK}" =~ "changed=1"|"ok=2" ]]; then
    log_pass "Handler do NGINX executou e recarregou com sucesso operacional."
else
    log_fail "Reload válido do NGINX falhou inesperadamente: ${OUTPUT_NGINX_OK}"
fi

log_test "Cenário 1.2: Reload do Prometheus com configuração válida deve responder HTTP 200 (exit code 0)"
set +e
OUTPUT_PROM_OK=$(ansible-playbook -i "${INVENTORY}" "${TEST_PLAYBOOK}" -e "test_target=prometheus_reload" 2>&1)
STATUS_PROM_OK=$?
set -e

if [[ ${STATUS_PROM_OK} -eq 0 && "${OUTPUT_PROM_OK}" =~ "ok=2" ]]; then
    log_pass "Handler do Prometheus executou POST /-/reload retornando HTTP 200."
else
    log_fail "Reload válido do Prometheus falhou inesperadamente: ${OUTPUT_PROM_OK}"
fi

# ------------------------------------------------------------------------------
# 2. Configuração inválida do NGINX deve interromper playbook antes/durante reload
# ------------------------------------------------------------------------------
log_test "Cenário 2: Configuração inválida do NGINX deve falhar explicitamente e interromper o playbook"
INVALID_NGINX_CONTENT="${ORIGINAL_NGINX_CONF}
### SINTAXE INVALIDA INJETADA ###
invalid_nginx_directive_token_test;
"
docker_write_file "${NGINX_CONF_PATH}" "${INVALID_NGINX_CONTENT}"

set +e
OUTPUT_NGINX_INVALID=$(ansible-playbook -i "${INVENTORY}" "${TEST_PLAYBOOK}" -e "test_target=nginx_validate" 2>&1)
STATUS_NGINX_INVALID=$?
set -e

# Restaura imediatamente
docker_write_file "${NGINX_CONF_PATH}" "${ORIGINAL_NGINX_CONF}"

if [[ ${STATUS_NGINX_INVALID} -ne 0 && "${OUTPUT_NGINX_INVALID}" =~ "failed"|"unknown directive" ]]; then
    log_pass "Configuração inválida foi bloqueada com erro explícito de validação (status ${STATUS_NGINX_INVALID})."
else
    log_fail "Erro sintático no NGINX não interrompeu a execução: ${OUTPUT_NGINX_INVALID}"
fi

# ------------------------------------------------------------------------------
# 3. Container NGINX parado deve resultar em falha explícita
# ------------------------------------------------------------------------------
log_test "Cenário 3: Container NGINX parado deve resultar em falha explícita no reload (não mascarada)"
echo -e "  Parando container NGINX temporariamente..."
docker compose -f "${COMPOSE_FILE}" stop nginx >/dev/null 2>&1

set +e
OUTPUT_NGINX_STOPPED=$(ansible-playbook -i "${INVENTORY}" "${TEST_PLAYBOOK}" -e "test_target=nginx_reload" 2>&1)
STATUS_NGINX_STOPPED=$?
set -e

# Reinicia container NGINX
docker compose -f "${COMPOSE_FILE}" start nginx >/dev/null 2>&1
sleep 2

if [[ ${STATUS_NGINX_STOPPED} -ne 0 && "${OUTPUT_NGINX_STOPPED}" =~ "failed=1"|"is not running" ]]; then
    log_pass "Falha explícita detectada ao tentar recarregar NGINX parado (exit code ${STATUS_NGINX_STOPPED})."
else
    log_fail "Falha de container parado foi mascarada: ${OUTPUT_NGINX_STOPPED}"
fi

# ------------------------------------------------------------------------------
# 4. Prometheus indisponível deve resultar em falha explícita
# ------------------------------------------------------------------------------
log_test "Cenário 4: Container Prometheus parado/indisponível deve resultar em falha explícita (Connection refused)"
echo -e "  Parando container Prometheus temporariamente..."
docker compose -f "${COMPOSE_FILE}" stop prometheus >/dev/null 2>&1

set +e
OUTPUT_PROM_STOPPED=$(ansible-playbook -i "${INVENTORY}" "${TEST_PLAYBOOK}" -e "test_target=prometheus_reload" 2>&1)
STATUS_PROM_STOPPED=$?
set -e

# Reinicia container Prometheus
docker compose -f "${COMPOSE_FILE}" start prometheus >/dev/null 2>&1
sleep 2

if [[ ${STATUS_PROM_STOPPED} -ne 0 && "${OUTPUT_PROM_STOPPED}" =~ "failed=1"|"Connection refused" ]]; then
    log_pass "Falha explícita detectada com Prometheus indisponível (Connection refused, exit code ${STATUS_PROM_STOPPED})."
else
    log_fail "Falha de Prometheus indisponível foi mascarada: ${OUTPUT_PROM_STOPPED}"
fi

# ------------------------------------------------------------------------------
# 5. Prometheus com regras/configuração inválidas deve falhar na validação promtool
# ------------------------------------------------------------------------------
log_test "Cenário 5: Regras de alerta inválidas no Prometheus devem ser rejeitadas pelo promtool antes do reload"
INVALID_PROM_RULES="${ORIGINAL_PROM_RULES}
  - alert: BrokenRuleSyntax
    expr: invalid_promql_syntax_error[[[
"
docker_write_file "${PROM_RULES_PATH}" "${INVALID_PROM_RULES}"

set +e
OUTPUT_PROM_INVALID=$(ansible-playbook -i "${INVENTORY}" "${TEST_PLAYBOOK}" -e "test_target=prometheus_validate" 2>&1)
STATUS_PROM_INVALID=$?
set -e

# Restaura configuração do Prometheus
docker_write_file "${PROM_RULES_PATH}" "${ORIGINAL_PROM_RULES}"

if [[ ${STATUS_PROM_INVALID} -ne 0 && "${OUTPUT_PROM_INVALID}" =~ "failed"|"FAILED" ]]; then
    log_pass "Configuração/regras inválidas rejeitadas pelo promtool com falha explícita (exit code ${STATUS_PROM_INVALID})."
else
    log_fail "promtool não barrou regras inválidas: ${OUTPUT_PROM_INVALID}"
fi

# ------------------------------------------------------------------------------
# 6. Validação de Idempotência e Smoke Test Geral
# ------------------------------------------------------------------------------
log_test "Cenário 6: Execução convergente do playbook com smoke test integrado"
set +e
OUTPUT_PLAYBOOK=$(ansible-playbook -i "${INVENTORY}" "${BASE_DIR}/ansible/site.yml" --tags nginx,monitoring,grafana,smoke_test -e "enable_become=false" -e "ansible_become=false" 2>&1)
STATUS_PLAYBOOK=$?
set -e

if [[ ${STATUS_PLAYBOOK} -eq 0 && "${OUTPUT_PLAYBOOK}" =~ "failed=0" && "${OUTPUT_PLAYBOOK}" =~ "OK: GET http://127.0.0.1:80/projeto-korp -> 200" ]]; then
    log_pass "Playbook executou com sucesso (failed=0) e smoke test validou status HTTP 200."
else
    log_fail "Falha na execução final do site.yml: ${OUTPUT_PLAYBOOK}"
fi

# ------------------------------------------------------------------------------
# Relatório Final
# ------------------------------------------------------------------------------
log_header "RELATÓRIO FINAL DA SUÍTE DE TESTES DE HANDLERS"
echo -e "Total de testes executados: ${BOLD}${TOTAL_TESTS}${NC}"
echo -e "Testes aprovados:           ${GREEN}${BOLD}${PASSED_TESTS}${NC}"
echo -e "Testes com falha:           ${RED}${BOLD}${FAILED_TESTS}${NC}"

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    echo -e "\n${GREEN}${BOLD}✓ SUCESSO ABSOLUTO: Todos os cenários do plano de handlers passaram com sucesso!${NC}\n"
    exit 0
else
    echo -e "\n${RED}${BOLD}✗ FALHA: ${FAILED_TESTS} teste(s) falharam na validação.${NC}\n"
    exit 1
fi

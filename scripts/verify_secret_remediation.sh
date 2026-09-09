#!/usr/bin/env bash
# ==============================================================================
# Script de Validação Automatizada da Remediação de Credenciais do Grafana
# Valida as 6 fases do PLANO_REMEDIACAO_CREDENCIAL_GRAFANA.md
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1" >&2
  exit 1
}

info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

TEMP_DIR=$(mktemp -d /tmp/remediation_test.XXXXXX)
cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

echo "=============================================================================="
echo "Iniciando Bateria de Testes: Remediação de Credencial do Grafana"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# Teste 1: Ausência de credenciais em texto puro ou fallbacks no repositório
# ------------------------------------------------------------------------------
info "1. Verificando ausência de senhas antigas e credenciais padrão nos arquivos..."
LEAKS=$(git grep -En "AdminSecure#2026|admin/admin" -- \
  ':!PLANO_REMEDIACAO_CREDENCIAL_GRAFANA.md' \
  ':!ansible/site.yml' \
  ':!.github/workflows/ci.yml' \
  ':!scripts/verify_secret_remediation.sh' || true)

if [ -n "${LEAKS}" ]; then
  echo "${LEAKS}"
  fail "Credenciais comprometidas encontradas no código ou documentação!"
fi
pass "Nenhuma credencial antiga ou fallback detectado nos arquivos monitorados."

# ------------------------------------------------------------------------------
# Teste 2: Confirmação de criptografia do Ansible Vault
# ------------------------------------------------------------------------------
info "2. Verificando integridade e criptografia de ansible/group_vars/vault.yml..."
if [ ! -f "ansible/group_vars/vault.yml" ]; then
  fail "Arquivo ansible/group_vars/vault.yml não encontrado!"
fi

HEADER=$(head -n 1 ansible/group_vars/vault.yml)
if [[ "${HEADER}" != "\$ANSIBLE_VAULT;"* ]]; then
  fail "ansible/group_vars/vault.yml NÃO está criptografado com Ansible Vault!"
fi
pass "ansible/group_vars/vault.yml está devidamente criptografado com Ansible Vault."

# ------------------------------------------------------------------------------
# Teste 3: Checagem sintática do playbook Ansible
# ------------------------------------------------------------------------------
info "3. Executando ansible-playbook --syntax-check..."
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --syntax-check > /dev/null
pass "Sintaxe do playbook ansible/site.yml validada com sucesso."

# ------------------------------------------------------------------------------
# Teste 4: Falha assertiva nos pre_tasks quando executado sem senha
# ------------------------------------------------------------------------------
info "4. Validando que execução sem Vault e sem variável falha nos pre_tasks..."
SET_ERR=0
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml \
  --tags pre_check -e enable_become=false > "${TEMP_DIR}/no_pass.log" 2>&1 || SET_ERR=$?

if [ ${SET_ERR} -eq 0 ]; then
  fail "O playbook deveria ter falhado por ausência de senha, mas teve sucesso!"
fi

if ! grep -q "A senha administrativa do Grafana (grafana_admin_password) é obrigatória" "${TEMP_DIR}/no_pass.log"; then
  cat "${TEMP_DIR}/no_pass.log"
  fail "Mensagem de erro de asserção esperada não foi encontrada nos logs!"
fi
pass "Falha assertiva confirmada nos pre_tasks quando nenhuma senha é informada."

# ------------------------------------------------------------------------------
# Teste 5: Rejeição assertiva de valores fracos/conhecidos ('admin' e 'AdminSecure#2026')
# ------------------------------------------------------------------------------
info "5. Validando rejeição de senhas fracas ou conhecidas..."
for WEAK_PASS in "admin" "AdminSecure#2026"; do
  SET_WEAK_ERR=0
  GRAFANA_ADMIN_PASSWORD="${WEAK_PASS}" ansible-playbook -i ansible/inventory/hosts.ini \
    ansible/site.yml --tags pre_check -e enable_become=false > "${TEMP_DIR}/weak_${WEAK_PASS}.log" 2>&1 || SET_WEAK_ERR=$?

  if [ ${SET_WEAK_ERR} -eq 0 ]; then
    fail "O playbook deveria ter rejeitado a senha insegura '${WEAK_PASS}'!"
  fi
done
pass "Senhas inseguras ('admin' e 'AdminSecure#2026') foram expressamente rejeitadas."

# ------------------------------------------------------------------------------
# Teste 6: Sucesso na execução com Ansible Vault de Laboratório
# ------------------------------------------------------------------------------
info "6. Validando execução com o Ansible Vault de laboratório..."
VAULT_PASS_FILE="${TEMP_DIR}/vault_pass.txt"
echo "korp-vault-lab-2026" > "${VAULT_PASS_FILE}"
chmod 600 "${VAULT_PASS_FILE}"

ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml \
  --tags pre_check --vault-password-file "${VAULT_PASS_FILE}" -e enable_become=false > "${TEMP_DIR}/vault_success.log" 2>&1

if ! grep -q 'ok=5' "${TEMP_DIR}/vault_success.log"; then
  cat "${TEMP_DIR}/vault_success.log"
  fail "Execução com Vault não completou todas as tarefas de pre_check com sucesso!"
fi
pass "Execução dos pre_tasks com Ansible Vault completada com sucesso."

# ------------------------------------------------------------------------------
# Teste 7: Validação do Compose raiz (desenvolvimento/lab)
# ------------------------------------------------------------------------------
info "7. Validando comportamento do docker compose raiz..."
COMPOSE_ERR=0
docker compose config > "${TEMP_DIR}/compose_no_env.log" 2>&1 || COMPOSE_ERR=$?

if [ ${COMPOSE_ERR} -eq 0 ]; then
  fail "docker compose config deveria ter falhado sem GRAFANA_ADMIN_PASSWORD!"
fi

if ! grep -q "required variable GRAFANA_ADMIN_PASSWORD is missing a value" "${TEMP_DIR}/compose_no_env.log"; then
  cat "${TEMP_DIR}/compose_no_env.log"
  fail "docker compose config não exibiu a mensagem de obrigatoriedade esperada!"
fi

# Sucesso com variável definida
GRAFANA_ADMIN_PASSWORD="TestPasswordSecure2026!" docker compose config > /dev/null
pass "Compose raiz exige obrigatoriamente a senha e valida com sucesso quando fornecida."

# ------------------------------------------------------------------------------
# Teste 8: Validação de no_log e ausência de vazamento de segredos
# ------------------------------------------------------------------------------
info "8. Validando mascaramento com no_log: true..."
if ! grep -A 20 "Validar credencial administrativa do Grafana" ansible/site.yml | grep -q "no_log: true"; then
  fail "Assert de validação de credencial em ansible/site.yml não contém no_log: true!"
fi

if ! grep -A 10 "Provisionar arquivo de ambiente protegido do Grafana" ansible/roles/grafana/tasks/main.yml | grep -q "no_log: true"; then
  fail "Task de template grafana.env em ansible/roles/grafana/tasks/main.yml não contém no_log: true!"
fi
pass "Diretiva no_log: true configurada em todas as tarefas que manipulam segredos."

# ------------------------------------------------------------------------------
# Teste 9: Linter Ansible em perfil de Produção
# ------------------------------------------------------------------------------
info "9. Executando ansible-lint no playbook principal..."
ansible-lint ansible/site.yml > "${TEMP_DIR}/ansible_lint.log" 2>&1
pass "ansible-lint concluído sem erros em perfil de produção."

echo "=============================================================================="
echo -e "${GREEN}TODOS OS CONTROLES E TESTES DE SEGURANÇA FORAM VALIDADOS COM SUCESSO!${NC}"
echo "=============================================================================="

# Automação de Infraestrutura com Ansible — Korp DevOps

Este diretório contém a automação completa, idempotente e reproduzível para o provisionamento e deploy da plataforma Korp em hosts Linux (Debian 12, Ubuntu 22.04 / 24.04 LTS).

---

## 1. Arquitetura da Solução

O playbook orquestra todos os componentes através de containers Docker organizados em duas redes segregadas:

```text
Cliente HTTP ---> Porta 80 ---> [NGINX (Reverse Proxy)]
                                       |  (korp_frontend)
                                       v
                                [http-server-projeto-korp:8080]
                                       |
                                       +---> (korp_backend)
                                       |           |
                                       v           v
                                [Prometheus] <--- [Grafana]
```

- **`korp_frontend`**: Rede de entrada que conecta o NGINX à aplicação Go. A porta `8080` da aplicação não é exposta no host.
- **`korp_backend`**: Rede interna para telemetria entre a aplicação Go (`/metrics`), o Prometheus (`9090`) e o Grafana (`3000`).

---

## 2. Estrutura de Diretórios

```text
ansible/
├── ansible.cfg                           # Configurações globais (pipelining, roles_path, saída YAML)
├── inventory/
│   ├── hosts.ini.example                 # Exemplo de inventário documentado (remoto e local)
│   └── hosts.ini                         # Inventário ativo
├── group_vars/
│   ├── all.yml.example                   # Exemplo de variáveis e segredos documentados
│   └── all.yml                           # Variáveis ativas da plataforma
├── requirements.yml                      # Coleções Ansible necessárias (community.docker)
├── site.yml                              # Playbook único de orquestração
├── roles/
│   ├── docker/                           # Validação de OS e instalação do Docker CE & Compose
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   └── tasks/main.yml
│   ├── application/                      # Sincronização de código, build da imagem e compose.yaml
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   ├── tasks/main.yml
│   │   └── templates/compose.yaml.j2
│   ├── nginx/                            # Configuração de proxy reverso e headers defensivos
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   ├── tasks/main.yml
│   │   └── templates/http-server-projeto-korp.conf.j2
│   ├── monitoring/                       # Configuração de scrape e alertas Prometheus
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   ├── tasks/main.yml
│   │   └── templates/
│   │       ├── prometheus.yml.j2
│   │       └── alerts.yml.j2
│   └── grafana/                          # Provisioning declarativo de datasources e dashboards
│       ├── defaults/main.yml
│       ├── tasks/main.yml
│       ├── templates/
│       │   ├── datasources.yml.j2
│       │   └── dashboards.yml.j2
│       └── files/http-server-projeto-korp-dashboard.json
└── README.md                             # Este guia
```

---

## 3. Pré-requisitos

1. **Control Node** (máquina que executa o Ansible):
   - Python 3.10+
   - `ansible-core` ou `ansible` (instalável via `pipx install ansible` ou `apt install ansible`)
   - Coleção `community.docker` instalada:
     ```bash
     ansible-galaxy collection install -r ansible/requirements.yml
     ```

2. **Managed Node** (host alvo):
   - Sistema operacional: Ubuntu 22.04/24.04 LTS ou Debian 12 (arquiteturas `x86_64` ou `aarch64/arm64`).
   - Usuário com privilégios de `sudo` sem senha ou configurado para elevação de privilégios (`become: true`).
   - Mínimo de 1 GB de RAM e 2 GB de espaço livre em disco.
   - Portas livres: `80` (NGINX), `9090` (Prometheus) e `3000` (Grafana).

---

## 4. Configuração do Inventário

Edite o arquivo `ansible/inventory/hosts.ini`:

### Execução Local (Self-hosted / Laboratório)
```ini
[korp_servers]
localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3
```

### Execução em Servidor Remoto via SSH
```ini
[korp_servers]
203.0.113.10 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_ed25519 ansible_python_interpreter=/usr/bin/python3
```

---

## 5. Execução do Playbook

### Validação Sintática Prévia
```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --syntax-check
```

### Senha do Ansible Vault no laboratório

Para tornar o desafio reproduzível em um repositório público, o Vault incluído neste
projeto usa intencionalmente uma senha pública e exclusiva para laboratório:

```text
korp-vault-lab-2026
```

Essa senha não deve ser reutilizada em produção. Em um ambiente real, solicite a senha
por um canal seguro ou use um gerenciador de segredos. A senha pode ser validada sem
exibir o conteúdo descriptografado:

```bash
if ansible-vault view ansible/group_vars/vault.yml --ask-vault-pass >/dev/null; then
  echo "Senha do Vault válida."
else
  echo "Senha do Vault inválida ou arquivo inacessível."
fi
```

### Execução Completa (Comandos Oficiais)

#### 1. Execução Padrão com Ansible Vault (Recomendado para Produção e Laboratório)
Utilize `--ask-vault-pass` para informar a senha do cofre de forma interativa:
```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --ask-vault-pass
```

> **Nota de Laboratório**: A senha acima é pública por decisão de projeto para permitir a execução do desafio. O arquivo `ansible/group_vars/vault.yml` deve continuar versionado apenas em formato criptografado.

#### 2. Execução com Arquivo de Senha do Vault
```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --vault-password-file /caminho/seguro/vault_pass
```

#### 3. Execução em CI/Laboratório via Variável de Ambiente
Caso utilize automações ou pipelines sem arquivo Vault:
```bash
GRAFANA_ADMIN_PASSWORD="SuaSenhaForte123!" ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml
```

### Execução com Tags Específicas
Você pode isolar tarefas utilizando tags:
```bash
# Apenas validação inicial e instalação do Docker
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags docker --ask-vault-pass

# Apenas deploy da aplicação e proxy
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags application,nginx --ask-vault-pass

# Apenas smoke test
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags smoke_test
```

---

## 6. Smoke Test e Validação de Aceite

No final da execução, o playbook executa automaticamente o smoke test contra `http://127.0.0.1/projeto-korp`, validando:
- Status HTTP `200 OK`
- Cabeçalho `Content-Type: application/json`
- Propriedade `nome: "Projeto Korp"`
- Propriedade `horario` em formato RFC 3339 UTC válido (`...Z`)

A saída esperada no console é exibida pelo debug:
```text
TASK [Smoke test: Exibir resultado oficial no console] *************************
ok: [localhost] => {
    "msg": [
        "OK: GET http://127.0.0.1:80/projeto-korp -> 200",
        "Resposta: {\"nome\":\"Projeto Korp\",\"horario\":\"2026-09-03T15:20:00Z\"}"
    ]
}
```

---

## 7. Idempotência e Segurança

- **Idempotência**: Uma segunda execução sequencial do playbook não altera arquivos nem recria containers se as configurações não tiverem sido modificadas (`changed=0` nas tasks de estado).
- **Backups**: Alterações no template NGINX criam backups automáticos da configuração anterior antes de aplicar novas diretivas.
- **Segurança de Segredos (Ansible Vault)**: Credenciais administrativas não possuem fallback e nunca são versionadas em texto simples.
  - **Cofre de Laboratório**: O repositório inclui `ansible/group_vars/vault.yml` criptografado com a senha de testes `korp-vault-lab-2026`.
  - **Produção e Rekey**: Para alterar a senha do cofre para o ambiente de produção:
    ```bash
    ansible-vault rekey ansible/group_vars/vault.yml
    ```
  - **Edição de Segredos**:
    ```bash
    ansible-vault edit ansible/group_vars/vault.yml
    ```
- **Proteção de Segredos no Host Alvo**:
  - As credenciais do Grafana são gravadas exclusivamente no arquivo `{{ app_base_dir }}/grafana/grafana.env` com permissões restritas `0600` e propriedade de `root:root`.
  - A task Ansible de provisionamento utiliza `no_log: true` para evitar que a credencial seja exposta em logs, relatórios ou execuções com `--diff`.
  - O arquivo `compose.yaml` gerado não contém credenciais em texto claro e possui permissões `0640`.
- **Persistência de Dados**: Volumes Docker do Prometheus e Grafana (`korp-prometheus-data`, `korp-grafana-data`) são preservados durante atualizações e deploys normais.

---

## 8. Procedimento Operacional de Rotação de Credenciais

Caso uma credencial seja comprometida ou precise de rotação periódica:

1. **Gerar uma nova credencial forte**:
   ```bash
   openssl rand -base64 24
   ```
2. **Atualizar o segredo no Ansible Vault**:
   ```bash
   ansible-vault edit ansible/group_vars/vault.yml
   ```
3. **Aplicar a rotação**:
   - **Novo Deploy / Ambiente Limpo**:
     Execute o playbook normalmente com `--ask-vault-pass`. O Grafana inicializará a base já com a nova senha.
   - **Ambiente Ativo com Volume Persistente**:
     Como o Grafana persiste a senha na base interna no primeiro boot, execute a rotação interna via CLI no container e aplique o playbook para sincronizar o arquivo de ambiente:
     ```bash
     docker exec -it grafana grafana-cli admin reset-admin-password "<nova_senha>"
     ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags grafana --ask-vault-pass
     ```
4. **Validar a rotação**:
   - Confirmar que a senha antiga retorna `HTTP 401 Unauthorized`:
     ```bash
     curl -s -o /dev/null -w "%{http_code}" -u "admin:<senha_antiga>" http://localhost:3000/api/user
     ```
   - Confirmar que a nova senha retorna `HTTP 200 OK`:
     ```bash
     curl -s -o /dev/null -w "%{http_code}" -u "admin:<nova_senha>" http://localhost:3000/api/user
     ```

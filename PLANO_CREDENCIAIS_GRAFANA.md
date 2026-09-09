# Plano de Implementação: Credenciais do Grafana

## Objetivo

Alinhar o comportamento do Grafana entre o Docker Compose local e o provisionamento via Ansible, eliminando senhas fixas de aparência produtiva do repositório público e documentando corretamente a troca da senha inicial.

A proposta terá dois modos claros:

- **Desenvolvimento/desafio:** `admin/admin`, com troca obrigatória no primeiro acesso.
- **Produção:** senha obrigatória via Ansible Vault ou variável de ambiente protegida, sem fallback público.

## 1. Política de credenciais

| Cenário | Usuário | Senha |
|---|---|---|
| Compose local sem configuração | `admin` | `admin` |
| Compose local com `.env` | configurável | configurável |
| Ansible em desenvolvimento | `admin` | `admin` |
| Ansible em produção | configurável | obrigatoriamente via segredo |

O valor `admin/admin` será tratado explicitamente como credencial de laboratório, não como senha segura. Qualquer senha pública fixa de aparência produtiva deverá ser removida completamente.

## 2. Ajustar o Compose local

Alterar `compose.yaml` para manter apenas os fallbacks de desenvolvimento:

```yaml
environment:
  GF_SECURITY_ADMIN_USER: \${GRAFANA_ADMIN_USER:-admin}
  GF_SECURITY_ADMIN_PASSWORD: \${GRAFANA_ADMIN_PASSWORD:-admin}
  GF_USERS_ALLOW_SIGN_UP: "false"
```

Criar `.env.example`:

```env
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin
```

O `.env` real deverá continuar ignorado pelo Git. O fluxo documentado será:

```bash
cp .env.example .env
docker compose up --build -d
```

## 3. Ajustar o Ansible

Remover a senha fixa de `ansible/group_vars/all.yml` e `ansible/group_vars/all.yml.example`.

A precedência recomendada será:

1. `vault_grafana_admin_password`;
2. variável de ambiente `GRAFANA_ADMIN_PASSWORD`;
3. `admin`, somente no modo de desenvolvimento.

Exemplo conceitual:

```yaml
grafana_admin_user: "{{ lookup('env', 'GRAFANA_ADMIN_USER') | default('admin', true) }}"

grafana_admin_password: >-
  {{ vault_grafana_admin_password
     | default(lookup('env', 'GRAFANA_ADMIN_PASSWORD'), true)
     | default('admin', true) }}
```

Adicionar uma variável explícita:

```yaml
deployment_environment: development
```

No `site.yml`, incluir validação para:

- permitir `admin` em `development`;
- rejeitar, em `production`, senha ausente;
- rejeitar, em `production`, senha igual a `admin`;
- rejeitar senhas muito curtas;
- rejeitar uso exclusivo do fallback público em produção.

As validações que manipulam credenciais deverão usar `no_log: true`.

## 4. Proteger o Compose gerado pelo Ansible

Atualmente, a senha é inserida diretamente no YAML gerado pelo Ansible. Isso deverá ser substituído por um arquivo de ambiente protegido:

```text
/opt/korp/.grafana.env
```

Permissões esperadas:

```text
owner: root
group: root
mode: 0600
```

Conteúdo gerado:

```env
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=...
GF_USERS_ALLOW_SIGN_UP=false
```

No Compose gerado:

```yaml
grafana:
  env_file:
    - .grafana.env
```

A task que cria `.grafana.env` deverá executar antes da validação `docker compose config`, usar o módulo `template`, aplicar `no_log: true` e notificar o restart da stack quando o arquivo mudar.

O conteúdo do segredo nunca deverá ser exibido no output do Ansible.

## 5. Documentação

Atualizar o `README.md` para substituir a indicação simples de `admin/admin` por uma explicação de credencial inicial:

- `admin/admin` é a credencial inicial do ambiente de desenvolvimento;
- o Grafana pode exigir troca da senha no primeiro acesso;
- uma senha customizada via `.env` pode não gerar essa tela;
- a senha é criada automaticamente apenas na primeira inicialização do volume;
- alterar a variável depois que `grafana-data` existe não altera a senha armazenada;
- `docker compose down` preserva os dados;
- `docker compose down -v` remove o volume e deve ser usado somente quando essa perda for desejada.

Atualizar também `ansible/README.md` com o uso de variável protegida:

```bash
export GRAFANA_ADMIN_PASSWORD='uma-senha-segura'
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml
```

Para produção, documentar o uso de Vault:

```bash
ansible-vault create ansible/group_vars/vault.yml
```

## 6. Rotação e recuperação de senha

O playbook não deverá tentar alterar automaticamente a senha de um Grafana já inicializado. A variável `GF_SECURITY_ADMIN_PASSWORD` é usada principalmente na criação inicial do usuário.

Procedimento documentado:

1. alterar o segredo no Vault ou na variável protegida;
2. atualizar o arquivo de ambiente;
3. alterar a senha pela interface do Grafana ou pelo comando oficial de reset;
4. reiniciar o serviço;
5. manter o volume existente.

`docker compose down -v` deverá ser reservado para reset destrutivo de laboratório, não para rotação normal de senha.

## 7. Testes

### 7.1 Validação estática

Executar:

```bash
docker compose config
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --syntax-check
ansible-lint ansible/site.yml
git diff --check
```

Verificar que a senha pública não existe mais:

```bash
rg -n "GF_SECURITY_ADMIN_PASSWORD" .
```

A ocorrência de `GF_SECURITY_ADMIN_PASSWORD` será permitida apenas em templates e documentação apropriada, nunca com senha fixa.

### 7.2 Compose local

Validar:

- subida sem `.env`;
- login inicial com `admin/admin`;
- solicitação de troca da senha;
- persistência após reiniciar containers;
- persistência após `docker compose down`;
- remoção completa somente após `docker compose down -v`.

### 7.3 Senha customizada

Criar um `.env` temporário e validar:

- recebimento da configuração pelo container;
- ausência do segredo no Git;
- login com a senha configurada;
- persistência da credencial após reinicialização.

### 7.4 Ansible

Validar:

- execução de desenvolvimento sem variável externa;
- execução com `GRAFANA_ADMIN_PASSWORD`;
- execução usando Ansible Vault;
- falha de produção sem segredo;
- arquivo `/opt/korp/.grafana.env` com modo `0600`;
- senha ausente do `compose.yaml` renderizado;
- segunda execução idempotente;
- nenhum segredo exposto no output.

## 8. Critérios de aceite

A implementação será considerada concluída quando:

- nenhuma senha pública fixa de aparência produtiva existir no repositório;
- README e Ansible descreverem o mesmo comportamento;
- `admin/admin` estiver limitado ao modo de desenvolvimento;
- produção exigir senha externa;
- nenhum segredo estiver em YAML versionado;
- o arquivo remoto de segredo tiver permissões `0600`;
- volumes existentes não forem removidos pelo playbook;
- dashboards, datasource e métricas forem preservados durante atualizações;
- `docker compose config`, `ansible --syntax-check` e `ansible-lint` passarem;
- o deploy for idempotente.

## 9. Sequência recomendada de commits

1. `docs: definir política de credenciais do Grafana`
2. `chore: adicionar env.example para Compose local`
3. `refactor: proteger credenciais no deploy Ansible`
4. `test: validar modos development e production`
5. `docs: documentar persistência, rotação e recuperação`

Essa abordagem mantém o desafio simples para execução local, mas evita que o repositório público publique uma senha falsa de produção ou que o Ansible grave credenciais diretamente na configuração do Compose.

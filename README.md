# http-server-projeto-korp

Serviço HTTP em Go desenvolvido como parte do desafio técnico Korp DevOps. O serviço expõe o endpoint de negócio `/projeto-korp`, endpoints operacionais de observabilidade (`/healthz` e `/metrics`), coleta automatizada via **Prometheus** e visualização em dashboard declarativo via **Grafana**, orquestrados via **Docker Compose**.

---

## 1. Visão Geral e Arquitetura

- **Linguagem**: Go (1.25+) utilizando a biblioteca padrão `net/http` e cliente Prometheus oficial (`github.com/prometheus/client_golang`).
- **Porta padrão da aplicação**: `8080` (configurável via variável de ambiente `PORT`).
- **Conteinerização**: Docker com build multi-stage, binário estático e usuário não-root para segurança.
- **Robustez operacional**: Timeouts defensivos de conexão, *graceful shutdown* com propagação de contexto e registry isolado de telemetria.
- **Observabilidade**:
  - Métricas expostas em `/metrics` no formato Prometheus;
  - Coleta automática pelo Prometheus (`job: http-server-projeto-korp`) a cada 5s;
  - Regra de alerta declarativa `ServiceDown` para detecção de indisponibilidade;
  - Provisionamento automatizado de fonte de dados e dashboard no Grafana.

### Topologia dos Serviços (Docker Compose)

```text
Host:8080 ---------------> http-server-projeto-korp:8080
                                 │ (/metrics)
                                 ▼ (scrape a cada 5s)
Host:9090 ---------------> prometheus:9090
                                 │ (datasource proxy)
                                 ▼
Host:3000 ---------------> grafana:3000 (dashboard provisionado)
```

---

## 2. Contratos HTTP

### 2.1 Endpoint de Negócio: `GET /projeto-korp`

| Item | Definição |
|---|---|
| **Método** | `GET` |
| **Rota** | `/projeto-korp` |
| **Corpo** | Vazio |
| **Status de sucesso** | `200 OK` |
| **Content-Type** | `application/json` |
| **Outros métodos** | `405 Method Not Allowed` (`Allow: GET`) |
| **Rotas não mapeadas** | `404 Not Found` |

#### Resposta de Exemplo (200 OK)
```json
{
  "nome": "Projeto Korp",
  "horario": "2026-09-03T15:04:05Z"
}
```

---

### 2.2 Endpoint de Prontidão: `GET /healthz`

Endpoint leve e sem efeitos colaterais para sondas de liveness/readiness (healthcheck do Docker e orquestradores).

| Item | Definição |
|---|---|
| **Método** | `GET` |
| **Rota** | `/healthz` |
| **Status de sucesso** | `200 OK` |
| **Content-Type** | `application/json` |
| **Resposta** | `{"status":"ok"}` |
| **Outros métodos** | `405 Method Not Allowed` |

---

### 2.3 Endpoint de Métricas: `GET /metrics`

Expõe métricas no formato padrão de texto do Prometheus:

- `http_requests_total{method, route, status}`: Contador particionado por método HTTP, rota normalizada (`/projeto-korp`, `/healthz` ou `not_found`) e status code.
- *Nota de design*: O endpoint `/metrics` é deliberadamente excluído de `http_requests_total` para que coletas periódicas não inflem o tráfego de negócio. A disponibilidade da coleta é monitorada via `up{job="http-server-projeto-korp"}`.
- Métricas padrão do runtime Go (`go_goroutines`, `go_memstats_*`) e de processo (`process_cpu_seconds_total`, etc.).

---

## 3. Orquestração Multi-Container (Docker Compose)

O ambiente completo de aplicação e observabilidade é orquestrado via `compose.yaml`.

### Configuração de variáveis de ambiente (Desenvolvimento Local)

Antes de iniciar os containers para desenvolvimento local ou laboratório, copie o arquivo de exemplo `.env.example` para `.env` e defina a senha administrativa do Grafana:

```bash
cp .env.example .env
# Edite o arquivo .env e configure uma senha forte em GRAFANA_ADMIN_PASSWORD
```

> [!IMPORTANT]
> O arquivo `.env` é destinado exclusivamente ao desenvolvimento local e laboratório.
> Para implantações oficiais e produção, utilize sempre a automação com **Ansible Vault** (`ansible/site.yml`), que garante isolamento, permissões `0600` e criptografia das credenciais.

### Subir o ambiente

```bash
docker compose up --build -d
```

### Serviços expostos

| Serviço | Porta Host | URL de Acesso | Descrição |
|---|---|---|---|
| `http-server-projeto-korp` | `8080` | `http://localhost:8080` | Aplicação Go |
| `prometheus` | `9090` | `http://localhost:9090` | Servidor Prometheus v3.2.1 |
| `grafana` | `3000` | `http://localhost:3000` | Painéis Grafana v11.5.2 (credencial definida via Vault ou `.env`) |

### Verificar estado dos containers

```bash
docker compose ps
```

### Encerrar o ambiente

```bash
docker compose down
```

Para remover também os volumes persistentes (`prometheus-data` e `grafana-data`):

```bash
docker compose down -v
```

---

## 4. Visualização e Dashboards no Grafana

O Grafana inicia pré-configurado com a fonte de dados Prometheus e o dashboard operacional:

- **Dashboard**: `HTTP Server Projeto Korp — Observabilidade` (UID: `http-server-projeto-korp-dash`)
- **Painéis**:
  1. **Disponibilidade do Serviço (`up`)**: Indicação clara de saúde (`ONLINE`, `OFFLINE` ou `SEM DADOS`);
  2. **Volume Total de Requisições (RPS)**: Taxa agregada de requisições por segundo (`sum(rate(http_requests_total[1m]))`);
  3. **Requisições por Rota e Status HTTP**: Visibilidade detalhada de tráfego e erros (`2xx`, `4xx`, `5xx`);
  4. **Total Acumulado por Status HTTP**: Contador volumétrico por código de retorno.

---

## 5. Testes Automatizados e Validação Estática

### Testes unitários com detector de concorrência

```bash
go test -v -race ./...
```

### Validação de formatação e tipagem

```bash
gofmt -l .
go vet ./...
```

### Validação de sintaxe do Prometheus e regras de alerta (com promtool)

```bash
docker run --rm -v "$(pwd)/deploy/prometheus:/etc/prometheus:ro" --entrypoint /bin/promtool prom/prometheus:v3.2.1 check config /etc/prometheus/prometheus.yml
docker run --rm -v "$(pwd)/deploy/prometheus:/etc/prometheus:ro" --entrypoint /bin/promtool prom/prometheus:v3.2.1 check rules /etc/prometheus/rules/alerts.yml
```

### Validação do schema do Compose

```bash
docker compose config
```
 
---
 
## 6. Orquestração Multi-Container com Docker Compose e NGINX Reverse Proxy
 
O ambiente completo de produção simulada opera com dois containers orquestrados via `compose.yaml`:
 
1. **`http-server-projeto-korp`**: Aplicação HTTP Go escutando internamente na porta `8080`.
2. **`nginx`**: Servidor NGINX oficial (`nginx:1.27-alpine`) atuando como proxy reverso e borda, escutando e publicando a porta `80` para o host.
 
### Arquitetura de Comunicação e Rede
 
```text
[ Cliente ]
    │ (http://localhost:80/projeto-korp)
    ▼
[ NGINX :80 ] (ponto único de entrada publicado no host)
    │
    │ Rede privada Docker bridge (korp-network)
    │ Resolução DNS interna: http://http-server-projeto-korp:8080
    ▼
[ http-server-projeto-korp :8080 ] (porta interna isolada, sem bind no host)
```
 
- **Isolamento de Rede**: A aplicação Go **não** possui a diretiva `ports` no Compose, tornando a porta `8080` inacessível a partir da máquina host. Toda comunicação externa deve passar obrigatoriamente pelo proxy NGINX.
- **Resiliência e Healthcheck**: O NGINX depende da integridade da aplicação (`depends_on` com `condition: service_healthy`). O healthcheck executa periodicamente `wget --spider --quiet http://127.0.0.1:8080/projeto-korp`.
- **Configuração NGINX Declarativa**: As diretivas de proxy estão em `nginx/conf.d/http-server-projeto-korp.conf`, montadas em modo somente leitura (`:ro`) no container NGINX.
 
### Comandos de Operação
 
#### Iniciar o ambiente com build em segundo plano
 
```bash
docker compose up -d --build
```
 
#### Verificar o status dos serviços e healthcheck
 
```bash
docker compose ps
```
 
Saída esperada:
```text
NAME                                               IMAGE                                            STATUS                    PORTS
korp-devops-challenge-http-server-projeto-korp-1   korp-devops-challenge-http-server-projeto-korp   Up (healthy)              8080/tcp
korp-devops-challenge-nginx-1                      nginx:1.27-alpine                                Up                        0.0.0.0:80->80/tcp
```
 
#### Testar a configuração do NGINX dentro do container
 
```bash
docker compose exec nginx nginx -t
```
 
#### Smoke test oficial (porta 80)
 
```bash
curl -i http://localhost:80/projeto-korp
```
 
Exemplo de resposta:
```http
HTTP/1.1 200 OK
Server: nginx/1.27.5
Content-Type: application/json
```

#### Acompanhar os logs da aplicação

```bash
docker compose logs -f http-server-projeto-korp
```
 
#### Encerrar o ambiente
 
```bash
docker compose down
```
 
---
 
## 7. Estrutura do Projeto
 
```text
.
├── .yamllint.yml                    # Regras de linting YAML padronizadas
├── ansible/                         # Automação de infraestrutura e orquestração Ansible
│   ├── ansible.cfg                  # Configurações do Ansible
│   ├── group_vars/                  # Variáveis globais da plataforma
│   ├── inventory/                   # Inventário de hosts gerenciados
│   ├── requirements.yml             # Dependências de coleções Ansible
│   ├── roles/                       # Roles: docker, application, nginx, monitoring, grafana
│   └── site.yml                     # Playbook principal de orquestração
├── cmd/
│   └── http-server-projeto-korp/
│       └── main.go                  # Ponto de entrada e graceful shutdown
├── compose.yaml                     # Orquestração multi-container da stack completa
├── deploy/
│   ├── grafana/
│   │   ├── dashboards/
│   │   │   └── http-server-projeto-korp.json  # Dashboard declarativo provisionado
│   │   └── provisioning/
│   │       ├── dashboards/dashboards.yml      # Provedor de dashboards
│   │       └── datasources/prometheus.yml     # Provedor de fonte de dados Prometheus
│   └── prometheus/
│       ├── prometheus.yml           # Configuração de scrape e regras
│       └── rules/
│           └── alerts.yml           # Alerta ServiceDown
├── Dockerfile                       # Build multi-stage e runtime seguro em Alpine
├── go.mod                           # Módulo Go e dependências
├── go.sum                           # Checksums das dependências
├── internal/
│   └── transport/
│       └── http/
│           ├── handler.go           # Roteamento de /projeto-korp, /healthz e /metrics
│           └── metrics.go           # Middleware de telemetria e isolamento de registry
├── nginx/
│   └── conf.d/
│       └── http-server-projeto-korp.conf      # VirtualHost do proxy reverso NGINX
├── tests/
│   ├── test_ansible_handlers.sh     # Suíte automatizada de testes de resiliência de handlers
│   ├── test_handlers.yml            # Playbook de isolamento para validação de handlers
│   └── unit/
│       └── internal/transport/http/
│           ├── handler_test.go      # Testes unitários do endpoint de negócio
│           └── metrics_test.go      # Testes de integridade, métricas e isolamento
└── README.md                        # Documentação da stack e guia operacional
```
 
---

## 8. Roteiro de Validação e Resolução de Problemas (Troubleshooting)

### Validação de fluxo operacional ponta a ponta

1. **Subir a stack**:
   ```bash
   docker compose up --build -d
   ```

2. **Verificar contratos via curl**:
   ```bash
   # Saúde
   curl -fsS http://localhost:8080/healthz
   # Métricas
   curl -fsS http://localhost:8080/metrics | grep http_requests_total
   # Negócio
   curl -fsS http://localhost:8080/projeto-korp
   # Prometheus
   curl -fsS http://localhost:9090/-/ready
   # Grafana
   curl -fsS http://localhost:3000/api/health
   ```

3. **Gerar tráfego para observação**:
   ```bash
   for i in {1..20}; do curl -s http://localhost:8080/projeto-korp > /dev/null; done
   for i in {1..5}; do curl -s -X POST http://localhost:8080/projeto-korp > /dev/null; done
   for i in {1..5}; do curl -s http://localhost:8080/rota-invalida > /dev/null; done
   ```

4. **Consultar série `up` no Prometheus**:
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=up' | grep -o '"value":\[[0-9.]*,"[0-9]"\]'
   ```

### Simulação de Falha e Recuperação (Disponibilidade)

1. **Simular queda da aplicação**:
   ```bash
   docker compose stop http-server-projeto-korp
   ```
2. **Observar indisponibilidade no Prometheus**:
   Após o scrape seguinte, `up{job="http-server-projeto-korp"}` passa para `0`.
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=up{job="http-server-projeto-korp"}'
   ```
3. **Observar alerta**:
   A regra `ServiceDown` entra no estado `pending` e posteriormente `firing` se a parada ultrapassar 1 minuto.
4. **Recuperar serviço**:
   ```bash
   docker compose start http-server-projeto-korp
   ```
   O target retorna ao estado `UP` (`up=1`) e o painel do Grafana volta ao status `ONLINE`.

---

## 9. Automação de Infraestrutura com Ansible (Parte 3)

Toda a plataforma (Docker, aplicação Go, NGINX como proxy reverso, Prometheus e Grafana provisionado) pode ser provisionada e configurada de forma totalmente automatizada, idempotente e reproduzível através do Ansible.

### Arquitetura da Topologia

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

- **Rede `korp_frontend`**: Conecta o NGINX à aplicação. A aplicação não expõe a porta `8080` diretamente no host.
- **Rede `korp_backend`**: Rede interna isolada para coleta de métricas pelo Prometheus e visualização pelo Grafana.
- **Provisionamento Declarativo**: Dashboards e datasources do Grafana são provisionados automaticamente via arquivos de configuração sem intervenção manual.

### Estrutura de Roles

```text
ansible/
├── ansible.cfg                           # Configurações globais (pipelining, saída YAML)
├── inventory/hosts.ini                   # Inventário configurável (hosts remotos e local)
├── group_vars/all.yml                    # Variáveis globais da plataforma e portas
├── requirements.yml                      # Coleções Ansible (community.docker, ansible.posix)
├── site.yml                              # Playbook único de entrada
└── roles/
    ├── docker/                           # Validação de OS e instalação do Docker CE & Compose
    ├── application/                      # Sincronização, build da imagem e compose.yaml
    ├── nginx/                            # VirtualHost NGINX, proxy reverso e headers
    ├── monitoring/                       # Scrape configs e regras de alerta Prometheus
    └── grafana/                          # Provisionamento declarativo de datasource e dashboard
```

### Pré-requisitos

1. **Control Node**:
   - `ansible-core` ou `ansible` (versão 2.16+)
   - Coleções necessárias instaladas:
     ```bash
     ansible-galaxy collection install -r ansible/requirements.yml
     ```
2. **Managed Node** (alvo):
   - Ubuntu 22.04/24.04 LTS ou Debian 12 (x86_64 ou arm64).
   - Usuário com acesso SSH e permissão de `sudo` (`become: true`).
   - Mínimo de 1 GB de RAM e 2 GB livres em disco.

### Comando Oficial de Execução

Após configurar o inventário em `ansible/inventory/hosts.ini`:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml
```

### Smoke Test Obrigatório

O playbook executa um teste de fumaça automático ao final do provisionamento contra `http://127.0.0.1/projeto-korp`, validando:
- Código HTTP `200 OK`
- `Content-Type: application/json`
- Objeto JSON contendo `nome == "Projeto Korp"` e `horario` em UTC (RFC 3339).

Saída esperada no console:
```text
TASK [Smoke test: Exibir resultado oficial no console] *************************
ok: [localhost] => {
    "msg": [
        "OK: GET http://127.0.0.1:80/projeto-korp -> 200",
        "Resposta: {\"nome\":\"Projeto Korp\",\"horario\":\"2026-09-03T15:30:00Z\"}"
    ]
}
```

### Validações de Qualidade e Idempotência

- **Validação Sintática**: `ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --syntax-check`
- **Linting de Boas Práticas**: `ansible-lint ansible/site.yml` (Aprovado em nível `production`)
- **Linting YAML**: `yamllint ansible/ .yamllint.yml` (Regras padronizadas via `.yamllint.yml`, zero erros/avisos)
- **Validação de Handlers e Resiliência**: `./tests/test_ansible_handlers.sh` (Suíte de 7 cenários cobrindo reload bem-sucedido, bloqueio de sintaxe inválida e fail-fast com container parado)
- **Idempotência**: Uma segunda execução consecutiva mantém `changed=0` nas configurações.

---

## 10. Guia de Testes e Validação Completa

A plataforma possui testes automatizados e procedimentos de verificação operacional para cada camada da arquitetura:

- **Testes Unitários Go (com detector de race conditions)**:
  ```bash
  go test -v -race ./...
  ```
- **Suíte de Testes Automatizada de Handlers Ansible (7 cenários)**:
  ```bash
  ./tests/test_ansible_handlers.sh
  ```
- **Validação Sintática do NGINX no Container**:
  ```bash
  docker compose exec -T nginx nginx -t
  ```
- **Validação de Configuração e Alertas do Prometheus via Promtool**:
  ```bash
  docker compose exec -T prometheus promtool check config /etc/prometheus/prometheus.yml
  docker compose exec -T prometheus promtool check rules /etc/prometheus/rules/alerts.yml
  ```
- **Smoke Test Oficial de Negócio via Proxy Reverso**:
  ```bash
  curl -i http://localhost:80/projeto-korp
  ```

### Queries Prometheus úteis

As principais consultas também são definidas como recording rules em
`ansible/roles/monitoring/templates/alerts.yml.j2`. Depois que o Prometheus
carregar as regras, elas podem ser consultadas em `http://localhost:9090/graph`:

```promql
korp:availability:avg1m
korp:requests:rate1m
korp:requests_by_status:rate1m
korp:errors:rate1m
```

O dashboard provisionado do Grafana permanece como a interface principal para
visualização histórica dessas métricas.

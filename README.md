# http-server-projeto-korp

Serviço HTTP em Go desenvolvido como parte do desafio técnico Korp DevOps. O serviço expõe o endpoint de negócio `/projeto-korp`, endpoints operacionais de observabilidade (`/healthz` e `/metrics`), coleta automatizada via **Prometheus** e visualização em dashboard declarativo via **Grafana**, orquestrados via **Docker Compose**.

## Início rápido

### Execução local

```bash
cp .env.example .env
docker compose up --build -d
```

Abra `http://localhost:3000` e use `admin/admin`, salvo se alterar as variáveis
no arquivo `.env`. Veja [Credenciais do Grafana](#credenciais-do-grafana) para
persistência e rotação da senha.

### Deploy com Ansible

Desenvolvimento:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml
```

Produção:

```bash
export GRAFANA_ADMIN_PASSWORD='uma-senha-segura'
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml \
  -e deployment_environment=production
```

O uso de Ansible Vault e as validações de produção estão descritos no
[README do Ansible](ansible/README.md).

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

### Subir o ambiente

```bash
cp .env.example .env
docker compose up --build -d
```

O arquivo `.env` é opcional e está ignorado pelo Git. Ajuste-o antes de subir a
stack se quiser credenciais diferentes das credenciais de laboratório.

### Serviços expostos

| Serviço | Porta Host | URL de Acesso | Descrição |
|---|---|---|---|
| `http-server-projeto-korp` | `8080` | `http://localhost:8080` | Aplicação Go |
| `prometheus` | `9090` | `http://localhost:9090` | Servidor Prometheus v3.2.1 |
| `grafana` | `3000` | `http://localhost:3000` | Painéis Grafana v11.5.2 |

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

### Credenciais do Grafana

No Compose local, o fallback explícito de desenvolvimento é `admin/admin`.
Para configurar outro usuário ou senha, copie `.env.example` para `.env` e
altere `GRAFANA_ADMIN_USER` e `GRAFANA_ADMIN_PASSWORD`. O arquivo `.env` não
deve ser versionado e esses valores não devem ser usados em produção.

Na primeira inicialização do volume `grafana-data`, o Grafana cria o usuário
administrador. Com `admin/admin`, ele pode solicitar a troca da senha no
primeiro acesso; uma senha customizada via `.env` pode não exibir essa tela.
Alterar a variável depois que o volume já existe não altera a senha armazenada.

`docker compose down` preserva os dados e a credencial. Use
`docker compose down -v` somente para um reset destrutivo de laboratório, pois
ele remove `grafana-data` e `prometheus-data`.

Para rotação normal, altere o segredo, troque a senha pela interface do Grafana
ou pelo comando oficial de reset, reinicie o serviço e mantenha o volume
existente.

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
 
## 7. Orquestração Multi-Container com Docker Compose e NGINX Reverse Proxy
 
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

## 6. Estrutura do Projeto

# Apenas o servidor Go
docker compose logs -f http-server-projeto-korp
```
 
#### Encerrar o ambiente
 
```bash
docker compose down
```
 
---
 
## 8. Estrutura do Projeto
 
```text
.
├── cmd/
│   └── http-server-projeto-korp/
│       └── main.go                  # Ponto de entrada e graceful shutdown
├── .env.example                      # Exemplo de credenciais locais do Grafana
├── compose.yaml                     # Orquestração da stack Go + Prometheus + Grafana
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
├── tests/
│   └── unit/
│       └── internal/transport/http/
│           ├── handler_test.go      # Testes unitários do endpoint de negócio
│           └── metrics_test.go      # Testes de integridade, métricas e isolamento
├── PLANO_IMPLEMENTACAO_MONITORAMENTO_OBSERVABILIDADE.md # Especificação da Parte 2
└── README.md                        # Documentação da stack e guia operacional
```
 
---

## 7. Roteiro de Validação e Resolução de Problemas (Troubleshooting)

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

## 8. Agentes e Skills do Projeto

As instruções locais para agentes ficam em `.agents/`. O ambiente esperado para a evolução do desafio inclui Docker, Docker Compose, Go, Ansible e Git.
 
Agentes especializados:
 
- `container-agent`: Docker, Docker Compose e redes Docker.
- `reverse-proxy-agent`: NGINX como proxy reverso.
- `observability-agent`: Prometheus, Grafana, alertas e provisioning.
- `infrastructure-agent`: Ansible, Linux/Shell e YAML de infraestrutura.
- `go-http-agent`: servidores HTTP e APIs em Go.
 
Skills disponíveis em `.agents/skills/`:
 
`go-http-server`, `docker`, `docker-compose`, `docker-networking`, `nginx-reverse-proxy`, `prometheus`, `grafana`, `observability`, `grafana-provisioning`, `ansible`, `linux-shell` e `yaml-infrastructure`.

As skills de infraestrutura foram criadas localmente após a verificação nominal da página [skills.sh/trending](https://www.skills.sh/trending), que não listava essas áreas no momento da configuração. CI/CD não foi adicionado porque permanece condicional no plano do desafio.

---

## 11. Automação de Infraestrutura com Ansible (Parte 3)

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
- **Linting YAML**: `yamllint ansible/` (Zero erros/avisos)
- **Idempotência**: Uma segunda execução consecutiva mantém `changed=0` nas configurações.

---

## 12. Guia de Testes e Validação Completa

Para a lista detalhada de todos os comandos de teste com suas **saídas esperadas reais** (Go, Docker, NGINX, Prometheus, Grafana e Ansible), consulte o guia oficial:

- **Documentação de Testes**: [TESTES.md](file:///mnt/codes/korp-devops-challenge/TESTES.md)
- **Script de Validação Automatizada (20 testes)**:
  ```bash
  ./tests/validate_platform.sh
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

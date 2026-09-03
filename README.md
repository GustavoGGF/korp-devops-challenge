# http-server-projeto-korp

Serviço HTTP em Go desenvolvido como parte do desafio técnico Korp DevOps. O serviço expõe o endpoint de negócio `/projeto-korp`, endpoints operacionais de observabilidade (`/healthz` e `/metrics`), coleta automatizada via **Prometheus** e visualização em dashboard declarativo via **Grafana**, orquestrados via **Docker Compose**.

---

## 1. Visão Geral e Arquitetura

- **Linguagem**: Go (1.24+) utilizando a biblioteca padrão `net/http` e cliente Prometheus oficial (`github.com/prometheus/client_golang`).
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
docker compose up --build -d
```

### Serviços expostos

| Serviço | Porta Host | URL de Acesso | Descrição |
|---|---|---|---|
| `http-server-projeto-korp` | `8080` | `http://localhost:8080` | Aplicação Go |
| `prometheus` | `9090` | `http://localhost:9090` | Servidor Prometheus v3.2.1 |
| `grafana` | `3000` | `http://localhost:3000` | Painéis Grafana v11.5.2 (user: `admin`, pass: `admin`) |

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

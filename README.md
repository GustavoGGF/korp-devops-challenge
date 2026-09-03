# http-server-projeto-korp

Serviço HTTP em Go desenvolvido como parte do desafio técnico Korp DevOps. O serviço expõe o endpoint `/projeto-korp` retornando informações em JSON com o horário atual calculado dinamicamente em UTC no formato RFC 3339.

---

## 1. Visão Geral

- **Linguagem**: Go (1.24+) utilizando a biblioteca padrão `net/http`.
- **Porta padrão**: `8080` (configurável via variável de ambiente `PORT`).
- **Conteinerização**: Docker com build multi-stage, binário estático e usuário não-root para segurança.
- **Robustez operacional**: Timeouts defensivos de conexão e *graceful shutdown* com propagação de contexto.

---

## 2. Contrato HTTP

### Endpoint: `GET /projeto-korp`

| Item | Definição |
|---|---|
| **Método** | `GET` |
| **Rota** | `/projeto-korp` |
| **Corpo da requisição** | Vazio |
| **Status de sucesso** | `200 OK` |
| **Content-Type** | `application/json` |
| **Outros métodos** | `405 Method Not Allowed` |
| **Rotas não mapeadas** | `404 Not Found` |

#### Formato da Resposta (200 OK)

```json
{
  "nome": "Projeto Korp",
  "horario": "2026-09-03T15:04:05Z"
}
```

- `nome`: String fixa `"Projeto Korp"`.
- `horario`: Timestamp em UTC gerado dinamicamente a cada requisição, em conformidade com a norma RFC 3339 (sufixo `Z`).

---

## 3. Pré-requisitos

- [Go](https://golang.org/dl/) 1.24 ou superior (para execução e testes locais).
- [Docker](https://docs.docker.com/get-docker/) (para compilação e execução via container).
- [Docker Compose](https://docs.docker.com/compose/) v2 ou superior (para orquestração multi-container e proxy reverso).
- `curl` (para testes de requisição via terminal).

---

## 4. Execução Local com Go

### Iniciar o servidor

```bash
go run ./cmd/http-server-projeto-korp
```

Para executar em uma porta diferente:

```bash
PORT=9090 go run ./cmd/http-server-projeto-korp
```

### Testar a requisição

```bash
curl -i http://localhost:8080/projeto-korp
```

Exemplo de resposta:

```http
HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 03 Sep 2026 13:35:00 GMT
Content-Length: 57

{"nome":"Projeto Korp","horario":"2026-09-03T13:35:00Z"}
```

---

## 5. Testes Automatizados

A aplicação segue práticas rigorosas de TDD e separação de responsabilidades. Os testes unitários cobrem contrato de resposta, cabeçalhos, integridade do formato UTC/RFC 3339, geração dinâmica de horário, rejeição de métodos inválidos e tratamento de rotas inexistentes.

Para executar os testes com detecção de concorrência (*race detector*):

```bash
go test -v -race ./...
```

Para validação estática e formatação de código:

```bash
gofmt -l .
go vet ./...
```

---

## 6. Build e Execução com Docker

### Construir a imagem Docker

```bash
docker build -t http-server-projeto-korp:local .
```

### Executar o container

```bash
docker run -d --name http-server-projeto-korp -p 8080:8080 http-server-projeto-korp:local
```

### Validar requisições no container

```bash
# 1. Requisição válida (200 OK)
curl -i http://localhost:8080/projeto-korp

# 2. Requisição com método não permitido (405 Method Not Allowed)
curl -i -X POST http://localhost:8080/projeto-korp

# 3. Rota não mapeada (404 Not Found)
curl -i http://localhost:8080/rota-invalida
```

### Parar e remover o container

```bash
docker stop http-server-projeto-korp && docker rm http-server-projeto-korp
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

{"nome":"Projeto Korp","horario":"2026-09-03T14:46:52Z"}
```
 
#### Validar isolamento da aplicação (porta 8080 não deve responder no host)
 
```bash
curl -i http://localhost:8080/projeto-korp
# Esperado: Falha de conexão (porta 8080 recusada no host)
```
 
#### Acompanhar logs dos containers
 
```bash
# Todos os serviços
docker compose logs -f

# Apenas o proxy NGINX
docker compose logs -f nginx

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
│       └── main.go                         # Ponto de entrada, configuração do servidor e graceful shutdown
├── internal/
│   └── transport/
│       └── http/
│           └── handler.go                  # Roteamento e handlers HTTP do endpoint /projeto-korp
├── nginx/
│   └── conf.d/
│       └── http-server-projeto-korp.conf   # Configuração do proxy reverso NGINX e headers defensivos
├── tests/
│   └── unit/
│       └── internal/transport/http/
│           └── handler_test.go             # Testes unitários automatizados do contrato HTTP
├── .dockerignore                           # Exclusão de arquivos desnecessários no build da imagem
├── .gitignore                              # Exclusões do versionamento Git
├── Dockerfile                              # Build multi-stage (golang:1.24-alpine) e runtime seguro (alpine:3.21)
├── compose.yaml                            # Orquestração Compose (Go Server + NGINX + rede bridge korp-network)
├── go.mod                                  # Definição do módulo Go
├── PLANO_IMPLEMENTACAO_HTTP_SERVER.md      # Plano de especificação da aplicação HTTP Go
├── PLANO_IMPLEMENTACAO_DOCKER_COMPOSE_NGINX.md # Plano de especificação da orquestração e proxy reverso
└── README.md                               # Documentação técnica e operacional do projeto
```
 
---
 
## 9. Detalhes de Segurança e Operação
 
- **Build Multi-stage e Imagens Versionadas**: A compilação é isolada no estágio `builder` (`golang:1.24-alpine`), gerando um binário estático (`CGO_ENABLED=0`) com símbolos removidos (`-s -w`). O runtime utiliza imagem mínima e controlada (`alpine:3.21`).
- **Mínimo Privilégio**: O container da aplicação Go executa sob o usuário não-privilegiado `appuser` (UID 10001).
- **Volume NGINX Somente Leitura**: A pasta de configuração `./nginx/conf.d` é montada como bind read-only (`:ro`), impedindo qualquer modificação no sistema de arquivos do NGINX em tempo de execução.
- **Timeouts Defensivos em Dupla Camada**:
  - **NGINX**: Conexão upstream em 5s (`proxy_connect_timeout`), leitura em 10s (`proxy_read_timeout`), escrita em 10s (`proxy_send_timeout`).
  - **Go HTTP Server**: `ReadHeaderTimeout` 5s, `ReadTimeout` 10s, `WriteTimeout` 10s, `IdleTimeout` 60s.
- **Graceful Shutdown**: Intercepta sinais `SIGINT` e `SIGTERM`, fornecendo 5 segundos para encerramento gracioso e drenagem de conexões ativas.
 
---
 
## 10. Resolução de Problemas (Troubleshooting)
 
### Porta 80 ou 8080 já está em uso na máquina host
 
1. **Identificar o processo em conflito**:
   ```bash
   lsof -i :80
   # ou
   ss -tulpn | grep -E ':(80|8080)\b'
   ```
 
2. **Alterar a porta na execução local do binário Go**:
   ```bash
   PORT=8081 go run ./cmd/http-server-projeto-korp
   curl -i http://localhost:8081/projeto-korp
   ```
 
3. **Alterar a porta mapeada no container isolado**:
   ```bash
   docker run -d --name http-server-projeto-korp -p 8081:8080 http-server-projeto-korp:local
   curl -i http://localhost:8081/projeto-korp
   ```
 
---
 
## 11. Agentes e skills do projeto
 
As instruções locais para agentes ficam em `.agents/`. O ambiente esperado para a evolução do desafio inclui Docker, Docker Compose, Go, Ansible e Git.
 
Agentes especializados:
 
- `container-agent`: Docker, Docker Compose e redes Docker.
- `reverse-proxy-agent`: NGINX como proxy reverso.
- `observability-agent`: Prometheus, Grafana, alertas e provisioning.
- `infrastructure-agent`: Ansible, Linux/Shell e YAML de infraestrutura.
- `go-http-agent`: servidores HTTP e APIs em Go.
 
Skills disponíveis em `.agents/skills/`:
 
`go-http-server`, `docker`, `docker-compose`, `docker-networking`, `nginx-reverse-proxy`, `prometheus`, `grafana`, `observability`, `grafana-provisioning`, `ansible`, `linux-shell` e `yaml-infrastructure`.

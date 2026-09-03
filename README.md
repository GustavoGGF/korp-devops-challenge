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

## 7. Estrutura do Projeto

```text
.
├── cmd/
│   └── http-server-projeto-korp/
│       └── main.go                  # Ponto de entrada, configuração do servidor e graceful shutdown
├── internal/
│   └── transport/
│       └── http/
│           └── handler.go           # Roteamento e handlers HTTP do endpoint /projeto-korp
├── tests/
│   └── unit/
│       └── internal/transport/http/
│           └── handler_test.go      # Testes unitários automatizados do contrato HTTP
├── Dockerfile                       # Build multi-stage e runtime seguro em Alpine
├── .dockerignore                    # Exclusão de arquivos desnecessários no build da imagem
├── go.mod                           # Definição do módulo Go
├── PLANO_IMPLEMENTACAO_HTTP_SERVER.md # Plano de especificação original
└── README.md                        # Documentação do serviço
```

---

## 8. Detalhes de Segurança e Operação

- **Build Multi-stage**: A compilação é isolada no estágio `builder` (`golang:alpine`), produzindo um binário estático sem dependências de CGO (`CGO_ENABLED=0`).
- **Imagem de Runtime Mínima**: Utiliza `alpine:latest` contendo apenas os certificados raiz de AC (`ca-certificates`) e dados de fuso (`tzdata`).
- **Usuário Não-Root**: O container executa sob o usuário não-privilegiado `appuser` (UID 10001).
- **Timeouts Defensivos**:
  - `ReadHeaderTimeout`: 5 segundos
  - `ReadTimeout`: 10 segundos
  - `WriteTimeout`: 10 segundos
  - `IdleTimeout`: 60 segundos
- **Graceful Shutdown**: Intercepta sinais `SIGINT` e `SIGTERM`, fornecendo um período de tolerância de 5 segundos para drenagem de conexões ativas.

---

## 9. Resolução de Problemas (Troubleshooting)

### Porta 8080 já está em uso

Se a porta `8080` já estiver ocupada por outro processo na máquina host:

1. **Identificar o processo em conflito**:
   ```bash
   lsof -i :8080
   # ou
   ss -tulpn | grep 8080
   ```

2. **Alterar a porta na execução local**:
   ```bash
   PORT=8081 go run ./cmd/http-server-projeto-korp
   curl -i http://localhost:8081/projeto-korp
   ```

---

## 10. Agentes e skills do projeto

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

3. **Alterar a porta mapeada no Docker**:
   ```bash
   docker run -d --name http-server-projeto-korp -p 8081:8080 http-server-projeto-korp:local
   curl -i http://localhost:8081/projeto-korp
   ```

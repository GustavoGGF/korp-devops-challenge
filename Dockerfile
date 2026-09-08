# Estágio de compilação (Builder)
FROM golang:1.24-alpine AS builder

WORKDIR /build

# Copia arquivos de definição do módulo Go
COPY go.mod go.sum ./
RUN go mod download

# Copia código-fonte da aplicação
COPY cmd/ ./cmd/
COPY internal/ ./internal/

# Compilação estática sem CGO, com remoção de símbolos de debug (-s -w)
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/http-server-projeto-korp ./cmd/http-server-projeto-korp

# Estágio de execução (Runtime)
FROM alpine:3.21

# Instala ca-certificates e tzdata, e configura usuário não-root
RUN apk --no-cache add ca-certificates tzdata && \
    addgroup -g 10001 appgroup && \
    adduser -u 10001 -G appgroup -D -s /sbin/nologin appuser

WORKDIR /app

# Copia o binário a partir do builder com permissões do appuser
COPY --from=builder --chown=appuser:appgroup /app/http-server-projeto-korp /app/http-server-projeto-korp

# Define usuário de execução não-privilegiado
USER appuser

EXPOSE 8080

ENTRYPOINT ["/app/http-server-projeto-korp"]

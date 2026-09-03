package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	transporthttp "http-server-projeto-korp/internal/transport/http"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	handler := transporthttp.NewHandler(nil)

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErrors := make(chan error, 1)

	go func() {
		log.Printf("Iniciando servidor http-server-projeto-korp na porta %s...", port)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErrors <- err
		}
	}()

	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, os.Interrupt, syscall.SIGTERM)

	select {
	case err := <-serverErrors:
		log.Fatalf("Erro fatal no servidor HTTP: %v", err)
	case sig := <-shutdown:
		log.Printf("Sinal recebido (%s). Iniciando shutdown gracioso...", sig)

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		if err := server.Shutdown(ctx); err != nil {
			log.Printf("Erro durante o shutdown do servidor: %v", err)
			if err := server.Close(); err != nil {
				log.Fatalf("Erro ao forçar fechamento do servidor: %v", err)
			}
		}
		log.Println("Servidor finalizado com sucesso.")
	}
}

package transporthttp

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// ProjetoKorpResponse representa o contrato de resposta do endpoint /projeto-korp.
type ProjetoKorpResponse struct {
	Nome    string `json:"nome"`
	Horario string `json:"horario"`
}

// HealthzResponse representa o contrato de resposta do endpoint /healthz.
type HealthzResponse struct {
	Status string `json:"status"`
}

// NewHandler configura e retorna o roteador HTTP da aplicação com métricas padrão isoladas.
func NewHandler(nowFunc func() time.Time) http.Handler {
	return NewHandlerWithMetrics(nowFunc, nil)
}

// NewHandlerWithRegistry configura e retorna o roteador HTTP usando um registry Prometheus explícito.
func NewHandlerWithRegistry(nowFunc func() time.Time, reg *prometheus.Registry) http.Handler {
	metrics := NewMetrics(reg)
	return NewHandlerWithMetrics(nowFunc, metrics)
}

// NewHandlerWithMetrics configura e retorna o roteador HTTP usando a instância de Metrics fornecida.
func NewHandlerWithMetrics(nowFunc func() time.Time, metrics *Metrics) http.Handler {
	if nowFunc == nil {
		nowFunc = time.Now
	}
	if metrics == nil {
		metrics = NewMetrics(nil)
	}

	mux := http.NewServeMux()

	// Endpoint de negócio /projeto-korp
	mux.HandleFunc("/projeto-korp", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/projeto-korp" {
			http.NotFound(w, r)
			return
		}

		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}

		w.Header().Set("Content-Type", "application/json")

		resp := ProjetoKorpResponse{
			Nome:    "Projeto Korp",
			Horario: nowFunc().UTC().Format(time.RFC3339),
		}

		if err := json.NewEncoder(w).Encode(resp); err != nil {
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			return
		}
	})

	// Endpoint leve de integridade /healthz
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/healthz" {
			http.NotFound(w, r)
			return
		}

		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		resp := HealthzResponse{Status: "ok"}
		if err := json.NewEncoder(w).Encode(resp); err != nil {
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			return
		}
	})

	// Endpoint de métricas Prometheus /metrics
	promHandler := promhttp.HandlerFor(metrics.Registry(), promhttp.HandlerOpts{})
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/metrics" {
			http.NotFound(w, r)
			return
		}

		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}

		promHandler.ServeHTTP(w, r)
	})

	// Aplica middleware de métricas ao redor do roteador
	return metrics.Instrument(mux)
}

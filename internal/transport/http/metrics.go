package transporthttp

import (
	"net/http"
	"strconv"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
)

// Metrics encapsula o registry do Prometheus e os coletores de métricas HTTP.
type Metrics struct {
	registry      *prometheus.Registry
	RequestsTotal *prometheus.CounterVec
}

// Registry retorna o Prometheus Registry configurado nesta instância de métricas.
func (m *Metrics) Registry() *prometheus.Registry {
	return m.registry
}

// NewMetrics inicializa uma nova instância de Metrics com um registry isolado ou fornecido.
func NewMetrics(reg *prometheus.Registry) *Metrics {
	if reg == nil {
		reg = prometheus.NewRegistry()
	}

	requestsTotal := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total de requisições HTTP processadas, particionadas por método, rota e status.",
		},
		[]string{"method", "route", "status"},
	)

	// Registra coletores padrão do runtime Go e métricas de processo
	reg.MustRegister(
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
		requestsTotal,
	)

	return &Metrics{
		registry:      reg,
		RequestsTotal: requestsTotal,
	}
}

type statusRecorder struct {
	http.ResponseWriter
	statusCode  int
	wroteHeader bool
}

func (r *statusRecorder) WriteHeader(code int) {
	if !r.wroteHeader {
		r.statusCode = code
		r.wroteHeader = true
		r.ResponseWriter.WriteHeader(code)
	}
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	if !r.wroteHeader {
		r.WriteHeader(http.StatusOK)
	}
	return r.ResponseWriter.Write(b)
}

// normalizeRoute mapeia o path da requisição para valores estáveis de baixa cardinalidade.
func normalizeRoute(path string) string {
	switch path {
	case "/projeto-korp":
		return "/projeto-korp"
	case "/healthz":
		return "/healthz"
	case "/metrics":
		return "/metrics"
	default:
		return "not_found"
	}
}

// Instrument intercepta requisições, captura status code e incrementa http_requests_total.
func (m *Metrics) Instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{
			ResponseWriter: w,
			statusCode:     http.StatusOK,
		}

		next.ServeHTTP(rec, r)

		route := normalizeRoute(r.URL.Path)
		// Exclui /metrics do volume de negócio para scrapes não inflacionarem o tráfego
		if route == "/metrics" {
			return
		}

		statusStr := strconv.Itoa(rec.statusCode)
		m.RequestsTotal.WithLabelValues(r.Method, route, statusStr).Inc()
	})
}

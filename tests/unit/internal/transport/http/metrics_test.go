package transporthttp_test

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"

	transporthttp "http-server-projeto-korp/internal/transport/http"
)

func TestHandler_Healthz_Success(t *testing.T) {
	handler := transporthttp.NewHandler(nil)

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("esperado status %d, obtido %d", http.StatusOK, rec.Code)
	}

	contentType := rec.Header().Get("Content-Type")
	if !strings.HasPrefix(contentType, "application/json") {
		t.Errorf("esperado Content-Type application/json, obtido %q", contentType)
	}

	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("falha ao decodificar JSON da resposta do healthz: %v", err)
	}

	if body["status"] != "ok" {
		t.Errorf("esperado status %q, obtido %q", "ok", body["status"])
	}
}

func TestHandler_Healthz_MethodNotAllowed(t *testing.T) {
	handler := transporthttp.NewHandler(nil)

	methods := []string{
		http.MethodPost,
		http.MethodPut,
		http.MethodDelete,
		http.MethodPatch,
	}

	for _, m := range methods {
		t.Run(m, func(t *testing.T) {
			req := httptest.NewRequest(m, "/healthz", nil)
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)

			if rec.Code != http.StatusMethodNotAllowed {
				t.Errorf("para método %s em /healthz, esperado status %d, obtido %d", m, http.StatusMethodNotAllowed, rec.Code)
			}
			allow := rec.Header().Get("Allow")
			if !strings.Contains(allow, http.MethodGet) {
				t.Errorf("esperado cabeçalho Allow contendo GET, obtido %q", allow)
			}
		})
	}
}

func TestHandler_Metrics_Exposition(t *testing.T) {
	reg := prometheus.NewRegistry()
	handler := transporthttp.NewHandlerWithRegistry(nil, reg)

	// Gera tráfego prévio para materializar a série http_requests_total no registry
	reqKorp := httptest.NewRequest(http.MethodGet, "/projeto-korp", nil)
	recKorp := httptest.NewRecorder()
	handler.ServeHTTP(recKorp, reqKorp)

	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("esperado status %d ao consultar /metrics, obtido %d", http.StatusOK, rec.Code)
	}

	contentType := rec.Header().Get("Content-Type")
	if !strings.Contains(contentType, "text/plain") {
		t.Errorf("esperado Content-Type text/plain, obtido %q", contentType)
	}

	body, err := io.ReadAll(rec.Body)
	if err != nil {
		t.Fatalf("erro ao ler corpo da resposta de /metrics: %v", err)
	}

	if !strings.Contains(string(body), "http_requests_total") {
		t.Errorf("esperado corpo de /metrics contendo métrica http_requests_total, obtido:\n%s", string(body))
	}
}

func TestHandler_Metrics_RequestsTotalIncrement(t *testing.T) {
	reg := prometheus.NewRegistry()
	metrics := transporthttp.NewMetrics(reg)
	handler := transporthttp.NewHandlerWithMetrics(nil, metrics)

	// 1. Requisição com sucesso para /projeto-korp
	req := httptest.NewRequest(http.MethodGet, "/projeto-korp", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("esperado status 200 para /projeto-korp, obtido %d", rec.Code)
	}

	countSuccess := testutil.ToFloat64(metrics.RequestsTotal.WithLabelValues(http.MethodGet, "/projeto-korp", "200"))
	if countSuccess != 1 {
		t.Errorf("esperado contador 1 para GET /projeto-korp 200, obtido %f", countSuccess)
	}

	// 2. Requisição com método não permitido para /projeto-korp
	reqMethodNotAllowed := httptest.NewRequest(http.MethodPost, "/projeto-korp", nil)
	recMethodNotAllowed := httptest.NewRecorder()
	handler.ServeHTTP(recMethodNotAllowed, reqMethodNotAllowed)

	if recMethodNotAllowed.Code != http.StatusMethodNotAllowed {
		t.Fatalf("esperado status 405, obtido %d", recMethodNotAllowed.Code)
	}

	countMethodNotAllowed := testutil.ToFloat64(metrics.RequestsTotal.WithLabelValues(http.MethodPost, "/projeto-korp", "405"))
	if countMethodNotAllowed != 1 {
		t.Errorf("esperado contador 1 para POST /projeto-korp 405, obtido %f", countMethodNotAllowed)
	}

	// 3. Rota não encontrada
	reqNotFound := httptest.NewRequest(http.MethodGet, "/nao-existe", nil)
	recNotFound := httptest.NewRecorder()
	handler.ServeHTTP(recNotFound, reqNotFound)

	if recNotFound.Code != http.StatusNotFound {
		t.Fatalf("esperado status 404, obtido %d", recNotFound.Code)
	}

	countNotFound := testutil.ToFloat64(metrics.RequestsTotal.WithLabelValues(http.MethodGet, "not_found", "404"))
	if countNotFound != 1 {
		t.Errorf("esperado contador 1 para GET not_found 404, obtido %f", countNotFound)
	}

	// 4. Teste de cardinalidade: rota com query string e parâmetros sensíveis
	reqSensitive := httptest.NewRequest(http.MethodGet, "/outra-rota?user=admin&token=supersecret123", nil)
	recSensitive := httptest.NewRecorder()
	handler.ServeHTTP(recSensitive, reqSensitive)

	if recSensitive.Code != http.StatusNotFound {
		t.Fatalf("esperado status 404, obtido %d", recSensitive.Code)
	}

	// Deve agrupar em "not_found", elevando o contador para 2, sem criar nova série com a URL suja
	countNotFoundAfter := testutil.ToFloat64(metrics.RequestsTotal.WithLabelValues(http.MethodGet, "not_found", "404"))
	if countNotFoundAfter != 2 {
		t.Errorf("esperado contador 2 para GET not_found 404 após URL com query, obtido %f", countNotFoundAfter)
	}

	// 5. Requisição para /healthz
	reqHealth := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	recHealth := httptest.NewRecorder()
	handler.ServeHTTP(recHealth, reqHealth)

	if recHealth.Code != http.StatusOK {
		t.Fatalf("esperado status 200 para /healthz, obtido %d", recHealth.Code)
	}

	countHealth := testutil.ToFloat64(metrics.RequestsTotal.WithLabelValues(http.MethodGet, "/healthz", "200"))
	if countHealth != 1 {
		t.Errorf("esperado contador 1 para GET /healthz 200, obtido %f", countHealth)
	}

	// 6. Requisição para /metrics: NÃO deve incrementar o contador de negócio
	reqMetrics := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	recMetrics := httptest.NewRecorder()
	handler.ServeHTTP(recMetrics, reqMetrics)

	if recMetrics.Code != http.StatusOK {
		t.Fatalf("esperado status 200 para /metrics, obtido %d", recMetrics.Code)
	}

	countMetricsRoute := testutil.ToFloat64(metrics.RequestsTotal.WithLabelValues(http.MethodGet, "/metrics", "200"))
	if countMetricsRoute != 0 {
		t.Errorf("esperado que /metrics NÃO incremente http_requests_total (obtido %f)", countMetricsRoute)
	}
}

func TestHandler_Metrics_RegistryIsolation(t *testing.T) {
	reg1 := prometheus.NewRegistry()
	metrics1 := transporthttp.NewMetrics(reg1)
	handler1 := transporthttp.NewHandlerWithMetrics(nil, metrics1)

	reg2 := prometheus.NewRegistry()
	metrics2 := transporthttp.NewMetrics(reg2)
	handler2 := transporthttp.NewHandlerWithMetrics(nil, metrics2)

	req1 := httptest.NewRequest(http.MethodGet, "/projeto-korp", nil)
	rec1 := httptest.NewRecorder()
	handler1.ServeHTTP(rec1, req1)

	// handler2 atende outra rota (/healthz)
	req2 := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec2 := httptest.NewRecorder()
	handler2.ServeHTTP(rec2, req2)

	val1Korp := testutil.ToFloat64(metrics1.RequestsTotal.WithLabelValues(http.MethodGet, "/projeto-korp", "200"))
	val2Korp := testutil.ToFloat64(metrics2.RequestsTotal.WithLabelValues(http.MethodGet, "/projeto-korp", "200"))
	val1Health := testutil.ToFloat64(metrics1.RequestsTotal.WithLabelValues(http.MethodGet, "/healthz", "200"))
	val2Health := testutil.ToFloat64(metrics2.RequestsTotal.WithLabelValues(http.MethodGet, "/healthz", "200"))

	if val1Korp != 1 {
		t.Errorf("handler1 deveria ter /projeto-korp com valor 1, obtido %f", val1Korp)
	}
	if val2Korp != 0 {
		t.Errorf("handler2 com registry isolado não deveria ter /projeto-korp, obtido %f", val2Korp)
	}
	if val1Health != 0 {
		t.Errorf("handler1 não deveria ter /healthz, obtido %f", val1Health)
	}
	if val2Health != 1 {
		t.Errorf("handler2 deveria ter /healthz com valor 1, obtido %f", val2Health)
	}
}

package transporthttp_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	transporthttp "http-server-projeto-korp/internal/transport/http"
)

func TestHandler_GetProjetoKorp_Success(t *testing.T) {
	fixedTime := time.Date(2026, time.September, 3, 15, 4, 5, 0, time.UTC)
	clock := func() time.Time {
		return fixedTime
	}

	handler := transporthttp.NewHandler(clock)

	req := httptest.NewRequest(http.MethodGet, "/projeto-korp", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	// 1. Status 200 OK
	if rec.Code != http.StatusOK {
		t.Fatalf("esperado status %d, obtido %d", http.StatusOK, rec.Code)
	}

	// 2. Content-Type: application/json
	contentType := rec.Header().Get("Content-Type")
	if !strings.HasPrefix(contentType, "application/json") {
		t.Errorf("esperado Content-Type application/json, obtido %q", contentType)
	}

	// 3 & 4 & 5. Validação do JSON
	var body transporthttp.ProjetoKorpResponse
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("falha ao decodificar JSON da resposta: %v", err)
	}

	if body.Nome != "Projeto Korp" {
		t.Errorf("esperado nome %q, obtido %q", "Projeto Korp", body.Nome)
	}

	if body.Horario == "" {
		t.Fatalf("campo horario não deve ser vazio")
	}

	parsedTime, err := time.Parse(time.RFC3339, body.Horario)
	if err != nil {
		t.Fatalf("horario não está no formato RFC 3339 válido: %v", err)
	}

	_, offset := parsedTime.Zone()
	if offset != 0 {
		t.Errorf("esperado horario com offset UTC (0), obtido %d", offset)
	}

	if !parsedTime.Equal(fixedTime) {
		t.Errorf("esperado horario %v, obtido %v", fixedTime, parsedTime)
	}
}

func TestHandler_GetProjetoKorp_DynamicTime(t *testing.T) {
	t1 := time.Date(2026, 9, 3, 10, 0, 0, 0, time.UTC)
	t2 := time.Date(2026, 9, 3, 10, 0, 5, 0, time.UTC)

	current := t1
	clock := func() time.Time {
		return current
	}

	handler := transporthttp.NewHandler(clock)

	// Primeira requisição
	req1 := httptest.NewRequest(http.MethodGet, "/projeto-korp", nil)
	rec1 := httptest.NewRecorder()
	handler.ServeHTTP(rec1, req1)

	var body1 transporthttp.ProjetoKorpResponse
	if err := json.NewDecoder(rec1.Body).Decode(&body1); err != nil {
		t.Fatalf("falha na requisição 1: %v", err)
	}

	// Avança o relógio
	current = t2

	// Segunda requisição
	req2 := httptest.NewRequest(http.MethodGet, "/projeto-korp", nil)
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)

	var body2 transporthttp.ProjetoKorpResponse
	if err := json.NewDecoder(rec2.Body).Decode(&body2); err != nil {
		t.Fatalf("falha na requisição 2: %v", err)
	}

	if body1.Horario == body2.Horario {
		t.Errorf("horários das requisições não devem ser iguais; devem ser dinâmicos: %s vs %s", body1.Horario, body2.Horario)
	}

	if body1.Horario != t1.Format(time.RFC3339) {
		t.Errorf("esperado %s, obtido %s", t1.Format(time.RFC3339), body1.Horario)
	}
	if body2.Horario != t2.Format(time.RFC3339) {
		t.Errorf("esperado %s, obtido %s", t2.Format(time.RFC3339), body2.Horario)
	}
}

func TestHandler_GetProjetoKorp_DefaultClock(t *testing.T) {
	// Testa que passar nil para o clock usa time.Now().UTC() por padrão
	handler := transporthttp.NewHandler(nil)

	before := time.Now().UTC().Add(-1 * time.Second)
	req := httptest.NewRequest(http.MethodGet, "/projeto-korp", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	after := time.Now().UTC().Add(1 * time.Second)

	if rec.Code != http.StatusOK {
		t.Fatalf("esperado status %d, obtido %d", http.StatusOK, rec.Code)
	}

	var body transporthttp.ProjetoKorpResponse
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("falha ao decodificar JSON: %v", err)
	}

	parsed, err := time.Parse(time.RFC3339, body.Horario)
	if err != nil {
		t.Fatalf("falha ao converter horario RFC3339: %v", err)
	}

	if parsed.Before(before) || parsed.After(after) {
		t.Errorf("horario gerado %v fora do intervalo esperado [%v, %v]", parsed, before, after)
	}
}

func TestHandler_MethodNotAllowed(t *testing.T) {
	methods := []string{
		http.MethodPost,
		http.MethodPut,
		http.MethodDelete,
		http.MethodPatch,
		http.MethodHead,
		http.MethodOptions,
	}

	handler := transporthttp.NewHandler(nil)

	for _, m := range methods {
		t.Run(m, func(t *testing.T) {
			req := httptest.NewRequest(m, "/projeto-korp", nil)
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)

			if rec.Code != http.StatusMethodNotAllowed {
				t.Errorf("para método %s, esperado status %d, obtido %d", m, http.StatusMethodNotAllowed, rec.Code)
			}
		})
	}
}

func TestHandler_NotFound(t *testing.T) {
	paths := []string{
		"/",
		"/projeto-korp/sub",
		"/outro",
		"/api/v1/projeto-korp",
	}

	handler := transporthttp.NewHandler(nil)

	for _, p := range paths {
		t.Run(p, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, p, nil)
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)

			if rec.Code != http.StatusNotFound {
				t.Errorf("para path %s, esperado status %d, obtido %d", p, http.StatusNotFound, rec.Code)
			}
		})
	}
}

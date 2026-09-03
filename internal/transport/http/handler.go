package transporthttp

import (
	"encoding/json"
	"net/http"
	"time"
)

// ProjetoKorpResponse representa o contrato de resposta do endpoint /projeto-korp.
type ProjetoKorpResponse struct {
	Nome    string `json:"nome"`
	Horario string `json:"horario"`
}

// NewHandler configura e retorna o roteador HTTP da aplicação.
func NewHandler(nowFunc func() time.Time) http.Handler {
	if nowFunc == nil {
		nowFunc = time.Now
	}

	mux := http.NewServeMux()

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

	return mux
}

// Webhook receiver for Agent Box
//
// Accepts inbound messages from phone and writes them to agent inbox files.
// Optionally can inject messages directly into tmux sessions.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

type InboxMessage struct {
	Agent   string `json:"agent"`
	Message string `json:"message"`
	Inject  bool   `json:"inject,omitempty"` // If true, also send to tmux
}

type Response struct {
	Success bool   `json:"success"`
	Message string `json:"message,omitempty"`
	Error   string `json:"error,omitempty"`
}

var (
	inboxDir    = getEnv("INBOX_DIR", "/data/inbox")
	listenAddr  = getEnv("WEBHOOK_ADDR", ":8080")
	authToken   = os.Getenv("WEBHOOK_AUTH_TOKEN") // Optional auth
	agentNameRe = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)
)

const (
	maxBodyBytes = int64(1 << 20) // 1MB
	tmuxTimeout  = 2 * time.Second
)

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/inbox", inboxHandler)
	http.HandleFunc("/agents", agentsHandler)
	http.HandleFunc("/send", sendHandler) // Alias for inbox with inject=true

	log.Printf("Webhook receiver starting on %s", listenAddr)
	log.Printf("Inbox directory: %s", inboxDir)
	if authToken != "" {
		log.Println("Auth token configured")
	}

	if err := os.MkdirAll(inboxDir, 0755); err != nil {
		log.Fatalf("failed to create inbox dir: %v", err)
	}

	server := &http.Server{
		Addr:              listenAddr,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(Response{Success: true, Message: "ok"})
}

func checkAuth(w http.ResponseWriter, r *http.Request) bool {
	if authToken == "" {
		return true
	}

	// Check Authorization header
	auth := r.Header.Get("Authorization")
	if auth == "Bearer "+authToken {
		return true
	}

	// Check query param
	if r.URL.Query().Get("token") == authToken {
		return true
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	json.NewEncoder(w).Encode(Response{Success: false, Error: "unauthorized"})
	return false
}

func inboxHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(Response{Success: false, Error: "method not allowed"})
		return
	}

	if !checkAuth(w, r) {
		return
	}

	msg, err := parseInboxMessage(w, r, false)
	if err != nil {
		return
	}
	deliverMessage(w, msg, "message delivered")
}

func sendHandler(w http.ResponseWriter, r *http.Request) {
	// Same as inbox but with inject=true by default
	if r.Method != http.MethodPost {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(Response{Success: false, Error: "method not allowed"})
		return
	}

	if !checkAuth(w, r) {
		return
	}

	msg, err := parseInboxMessage(w, r, true)
	if err != nil {
		return
	}
	deliverMessage(w, msg, "message sent")
}

func agentsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(Response{Success: false, Error: "method not allowed"})
		return
	}
	if !checkAuth(w, r) {
		return
	}

	// List tmux sessions
	output, err := tmuxOutput("ls", "-F", "#{session_name}")
	if err != nil {
		// No sessions
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"agents":  []string{},
		})
		return
	}

	agents := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(agents) == 1 && agents[0] == "" {
		agents = []string{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"agents":  agents,
	})
}

func injectToTmux(session, message string) error {
	// Check if session exists
	if err := tmuxRun("has-session", "-t", session); err != nil {
		return fmt.Errorf("session not found: %s", session)
	}

	// Send keys to tmux
	// This types the message into the active pane
	return tmuxRun("send-keys", "-t", session, message, "Enter")
}

func respondError(w http.ResponseWriter, msg string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(Response{Success: false, Error: msg})
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

func parseInboxMessage(w http.ResponseWriter, r *http.Request, injectDefault bool) (InboxMessage, error) {
	var msg InboxMessage

	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	defer r.Body.Close()

	contentType := r.Header.Get("Content-Type")
	if strings.Contains(contentType, "application/json") {
		decoder := json.NewDecoder(r.Body)
		if err := decoder.Decode(&msg); err != nil {
			var maxErr *http.MaxBytesError
			if errors.As(err, &maxErr) {
				respondError(w, "request body too large", http.StatusRequestEntityTooLarge)
				return InboxMessage{}, err
			}
			respondError(w, "invalid JSON", http.StatusBadRequest)
			return InboxMessage{}, err
		}
	} else {
		if err := r.ParseForm(); err != nil {
			respondError(w, "invalid form data", http.StatusBadRequest)
			return InboxMessage{}, err
		}
		msg.Agent = r.FormValue("agent")
		msg.Message = r.FormValue("message")
		msg.Inject = r.FormValue("inject") == "true" || r.FormValue("inject") == "1"
	}

	if injectDefault {
		msg.Inject = msg.Inject || injectDefault
	}

	if msg.Agent == "" {
		respondError(w, "agent name required", http.StatusBadRequest)
		return InboxMessage{}, fmt.Errorf("missing agent name")
	}
	if !agentNameRe.MatchString(msg.Agent) {
		respondError(w, "invalid agent name", http.StatusBadRequest)
		return InboxMessage{}, fmt.Errorf("invalid agent name")
	}
	if msg.Message == "" {
		respondError(w, "message required", http.StatusBadRequest)
		return InboxMessage{}, fmt.Errorf("missing message")
	}

	return msg, nil
}

func deliverMessage(w http.ResponseWriter, msg InboxMessage, okMessage string) {
	inboxFile := filepath.Join(inboxDir, msg.Agent+".txt")
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	entry := fmt.Sprintf("[%s] %s\n", timestamp, msg.Message)

	if err := os.MkdirAll(inboxDir, 0755); err != nil {
		respondError(w, "failed to create inbox directory", http.StatusInternalServerError)
		return
	}

	f, err := os.OpenFile(inboxFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		respondError(w, "failed to write to inbox", http.StatusInternalServerError)
		return
	}
	defer f.Close()

	if _, err := f.WriteString(entry); err != nil {
		respondError(w, "failed to write to inbox", http.StatusInternalServerError)
		return
	}

	log.Printf("Inbox message for %s: %s", msg.Agent, truncate(msg.Message, 50))

	if msg.Inject {
		if err := injectToTmux(msg.Agent, msg.Message); err != nil {
			log.Printf("Warning: failed to inject to tmux: %v", err)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(Response{Success: true, Message: okMessage})
}

func tmuxOutput(args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), tmuxTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "tmux", args...)
	output, err := cmd.Output()
	if ctx.Err() == context.DeadlineExceeded {
		return nil, fmt.Errorf("tmux command timed out")
	}
	return output, err
}

func tmuxRun(args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), tmuxTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "tmux", args...)
	if err := cmd.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return fmt.Errorf("tmux command timed out")
		}
		return err
	}
	return nil
}

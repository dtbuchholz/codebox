// Webhook receiver for Agent Box
//
// Accepts inbound messages from phone and writes them to agent inbox files.
// Optionally can inject messages directly into tmux sessions.
package main

import (
	"encoding/json"
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
	inboxDir     = getEnv("INBOX_DIR", "/data/inbox")
	listenAddr   = getEnv("WEBHOOK_ADDR", ":8080")
	authToken    = os.Getenv("WEBHOOK_AUTH_TOKEN") // Optional auth
	agentNameRe  = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)
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

	if err := http.ListenAndServe(listenAddr, nil); err != nil {
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

	var msg InboxMessage

	// Support both JSON and form data
	contentType := r.Header.Get("Content-Type")
	if strings.Contains(contentType, "application/json") {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			respondError(w, "failed to read body", http.StatusBadRequest)
			return
		}
		if err := json.Unmarshal(body, &msg); err != nil {
			respondError(w, "invalid JSON", http.StatusBadRequest)
			return
		}
	} else {
		// Form data
		msg.Agent = r.FormValue("agent")
		msg.Message = r.FormValue("message")
		msg.Inject = r.FormValue("inject") == "true" || r.FormValue("inject") == "1"
	}

	// Validate
	if msg.Agent == "" {
		respondError(w, "agent name required", http.StatusBadRequest)
		return
	}
	if !agentNameRe.MatchString(msg.Agent) {
		respondError(w, "invalid agent name", http.StatusBadRequest)
		return
	}
	if msg.Message == "" {
		respondError(w, "message required", http.StatusBadRequest)
		return
	}

	// Write to inbox file
	inboxFile := filepath.Join(inboxDir, msg.Agent+".txt")
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	entry := fmt.Sprintf("[%s] %s\n", timestamp, msg.Message)

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

	// Optionally inject into tmux
	if msg.Inject {
		if err := injectToTmux(msg.Agent, msg.Message); err != nil {
			// Don't fail the request, just log
			log.Printf("Warning: failed to inject to tmux: %v", err)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(Response{Success: true, Message: "message delivered"})
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

	agent := r.FormValue("agent")
	message := r.FormValue("message")

	if agent == "" || message == "" {
		respondError(w, "agent and message required", http.StatusBadRequest)
		return
	}

	if !agentNameRe.MatchString(agent) {
		respondError(w, "invalid agent name", http.StatusBadRequest)
		return
	}

	// Write to inbox
	inboxFile := filepath.Join(inboxDir, agent+".txt")
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	entry := fmt.Sprintf("[%s] %s\n", timestamp, message)

	f, err := os.OpenFile(inboxFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		respondError(w, "failed to write to inbox", http.StatusInternalServerError)
		return
	}
	f.WriteString(entry)
	f.Close()

	// Inject to tmux
	if err := injectToTmux(agent, message); err != nil {
		log.Printf("Warning: failed to inject to tmux: %v", err)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(Response{Success: true, Message: "message sent"})
}

func agentsHandler(w http.ResponseWriter, r *http.Request) {
	if !checkAuth(w, r) {
		return
	}

	// List tmux sessions
	cmd := exec.Command("tmux", "ls", "-F", "#{session_name}")
	output, err := cmd.Output()
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
	checkCmd := exec.Command("tmux", "has-session", "-t", session)
	if err := checkCmd.Run(); err != nil {
		return fmt.Errorf("session not found: %s", session)
	}

	// Send keys to tmux
	// This types the message into the active pane
	cmd := exec.Command("tmux", "send-keys", "-t", session, message, "Enter")
	return cmd.Run()
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

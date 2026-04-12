package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"path/filepath"

	"github.com/gorilla/websocket"
)

// To use godotenv if needed, but we can just implement a simple .env loader
// since we want proxy.go to behave exactly like proxy.js require('dotenv').config()
func loadDotEnv() {
    exePath, err := os.Executable()
    if err != nil {
        log.Printf("Warning: Could not determine executable path: %v", err)
        return
    }
    
    exeDir := filepath.Dir(exePath)
    envPath := filepath.Join(exeDir, ".env")
    
    file, err := os.Open(envPath)
	if err != nil {
		return
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if len(line) == 0 || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])
			// Strip quotes if any
			val = strings.Trim(val, `"'`)
			os.Setenv(key, val)
		}
	}
}

type ClientState struct {
	localSocket  *websocket.Conn
	remoteSocket *websocket.Conn
	roomID       string
	hostID       string
	messageQueue [][]byte
	mu           sync.Mutex
}

var (
	localPort    string
	remoteURL    string
	localClients sync.Map
	nextLocalID  uint64
	upgrader     = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}
)

func createLocalID() string {
	id := atomic.AddUint64(&nextLocalID, 1)
	return fmt.Sprintf("L%d_%d", id, time.Now().UnixMilli())
}

func main() {
	loadDotEnv()

	localPort = os.Getenv("LOCAL_PORT")
	if localPort == "" {
		localPort = "8080"
	}
	remoteURL = os.Getenv("REMOTE_URL")

	if remoteURL == "" {
		fmt.Fprintln(os.Stderr, "Error: REMOTE_URL environment variable is required")
		os.Exit(1)
	}

	server := &http.Server{
		Addr:    "0.0.0.0:" + localPort,
		Handler: http.HandlerFunc(handleHTTP),
	}

	// Handle graceful shutdown
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, os.Interrupt)
		<-sigChan
		
		fmt.Println("\nShutting down proxy...")
		localClients.Range(func(key, value interface{}) bool {
			state := value.(*ClientState)
			state.mu.Lock()
			if state.remoteSocket != nil {
				state.remoteSocket.Close()
			}
			if state.localSocket != nil {
				state.localSocket.Close()
			}
			state.mu.Unlock()
			return true
		})
		
		server.Close()
		fmt.Println("Proxy stopped.")
		os.Exit(0)
	}()

	fmt.Println(strings.Repeat("=", 60))
	fmt.Println("DevilBridge Local Proxy Server")
	fmt.Println(strings.Repeat("=", 60))
	fmt.Printf("Local WebSocket endpoint: ws://0.0.0.0:%s\n", localPort)
	fmt.Printf("Local HTTP endpoint: http://0.0.0.0:%s\n", localPort)
	fmt.Printf("Remote server: %s\n", remoteURL)
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println("\nProxy is running! Connect your game client to:")
	fmt.Printf("   ws://localhost:%s\n", localPort)
	fmt.Println("\nStatus page available at:")
	fmt.Printf("   http://localhost:%s\n", localPort)
	fmt.Println(strings.Repeat("=", 60))

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

func handleHTTP(w http.ResponseWriter, r *http.Request) {
	// Equivalent to parsing upgrade or normal request
	if r.Header.Get("Upgrade") == "websocket" {
		handleWebSocket(w, r)
		return
	}

	fmt.Printf("%s %s\n", r.Method, r.URL.Path)

	if r.Method == "GET" && r.URL.Path == "/" {
		w.Header().Set("Content-Type", "text/html")
		
		count := 0
		clientsHTML := ""
		localClients.Range(func(key, value interface{}) bool {
			count++
			id := key.(string)
			state := value.(*ClientState)
			room := state.roomID
			if room == "" {
				room = "None"
			}
			isHost := "No"
			if state.hostID == id {
				isHost = "Yes"
			}
			clientsHTML += fmt.Sprintf(`
                    <div class="client">
                        <pre>ID: %s<br>Room: %s<br>Host: %s</pre>
                    </div>
                `, id, room, isHost)
			return true
		})
		
		if count == 0 {
			clientsHTML = "<p>No active connections</p>"
		}

		html := fmt.Sprintf(`<!DOCTYPE html>
        <html>
        <head>
            <title>DevilBridge Local Proxy</title>
            <style>
                body { font-family: monospace; padding: 2rem; background: #1e1e1e; color: #d4d4d4; }
                h1 { color: #4ec9b0; }
                .status { background: #2d2d2d; padding: 1rem; border-radius: 5px; margin: 1rem 0; }
                .connected { color: #4ec9b0; }
                .disconnected { color: #f48771; }
                .client { background: #252526; padding: 0.5rem; margin: 0.5rem 0; border-left: 3px solid #4ec9b0; }
                pre { margin: 0; }
            </style>
        </head>
        <body>
            <h1>DevilBridge Local Proxy</h1>
            <div class="status">
                <strong>Status:</strong> <span class="connected">RUNNING</span><br>
                <strong>Remote Server:</strong> %s<br>
                <strong>Active Clients:</strong> <span id="clientCount">%d</span>
            </div>
            <h2>Active Connections</h2>
            <div id="clients">
                %s
            </div>
            <p style="margin-top: 2rem; font-size: 0.8rem;">Connect using: <strong>ws://localhost:8080</strong></p>
        </body>
        </html>`, remoteURL, count, clientsHTML)
        
		w.Write([]byte(html))
	} else if r.Method == "GET" && r.URL.Path == "/status" {
		w.Header().Set("Content-Type", "application/json")
		
		clientsArr := make([]map[string]interface{}, 0)
		localClients.Range(func(key, value interface{}) bool {
			id := key.(string)
			state := value.(*ClientState)
			clientsArr = append(clientsArr, map[string]interface{}{
				"id":     id,
				"roomId": state.roomID,
				"isHost": state.hostID == id,
			})
			return true		
		})
		
		resp := map[string]interface{}{
			"status": "running",
			"remoteServer": remoteURL,
			"activeClients": len(clientsArr),
			"clients": clientsArr,
		}
		json.NewEncoder(w).Encode(resp)
	} else {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte("Not found"))
	}
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	localSocket, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Printf("Upgrade error: %v\n", err)
		return
	}

	localClientID := createLocalID()
	fmt.Printf("[LOCAL] New client connected: %s\n", localClientID)

	state := &ClientState{
		localSocket:  localSocket,
		messageQueue: make([][]byte, 0),
	}
	localClients.Store(localClientID, state)

	fmt.Printf("[REMOTE] Connecting to remote server for %s...\n", localClientID)
	
	dialer := websocket.DefaultDialer
	remoteSocket, _, err := dialer.Dial(remoteURL, nil)
	if err != nil {
		fmt.Printf("[REMOTE] Failed to create connection for %s: %v\n", localClientID, err)
		localSocket.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(1011, "Internal Error"), time.Now().Add(time.Second))
		localSocket.Close()
		localClients.Delete(localClientID)
		return
	}
	
	state.mu.Lock()
	state.remoteSocket = remoteSocket
	queue := state.messageQueue
	state.messageQueue = nil // empty it out
	state.mu.Unlock()

	fmt.Printf("[REMOTE] Connected for client %s\n", localClientID)

	// Send queued messages
	for _, msgData := range queue {
		err := remoteSocket.WriteMessage(websocket.TextMessage, msgData)
		if err != nil {
			fmt.Printf("[REMOTE] Error sending queued message for %s: %v\n", localClientID, err)
		}
	}

	// Read from remote
	go func() {
		defer func() {
			fmt.Printf("[REMOTE] Disconnected for client %s\n", localClientID)
			
			state.mu.Lock()
			if state.localSocket != nil {
				errMsg, _ := json.Marshal(map[string]string{
					"type": "ERROR",
					"message": "Connection to remote server lost",
				})
				state.localSocket.WriteMessage(websocket.TextMessage, errMsg)
				state.localSocket.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(1011, "Remote connection lost"), time.Now().Add(time.Second))
				state.localSocket.Close()
			}
			state.mu.Unlock()
			localClients.Delete(localClientID)
		}()

		for {
			_, message, err := remoteSocket.ReadMessage()
			if err != nil {
				return
			}
			
			msgStr := string(message)
			fmt.Printf("[PROXY] Remote -> Local (%s): %s\n", localClientID, msgStr)
			
			var msg map[string]interface{}
			if json.Unmarshal(message, &msg) == nil {
				msgType, _ := msg["type"].(string)
				
				state.mu.Lock()
				if msgType == "ROOM_CREATED" {
					if code, ok := msg["code"].(string); ok {
						state.roomID = code
						state.hostID = localClientID
					}
				} else if msgType == "JOIN_SUCCESS" {
					if code, ok := msg["code"].(string); ok {
						state.roomID = code
					}
				} else if msgType == "ROOM_CLOSED" {
					state.roomID = ""
					state.hostID = ""
				}
				state.mu.Unlock()
			} else {
				fmt.Printf("[PROXY] Error parsing remote message: %v\n", err)
			}
			
			state.mu.Lock()
			if state.localSocket != nil {
				state.localSocket.WriteMessage(websocket.TextMessage, message)
			}
			state.mu.Unlock()
		}
	}()

	// Read from local
	go func() {
		defer func() {
			fmt.Printf("[LOCAL] Client disconnected: %s\n", localClientID)
			state.mu.Lock()
			if state.remoteSocket != nil {
				state.remoteSocket.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(1000, "Local client disconnected"), time.Now().Add(time.Second))
				state.remoteSocket.Close()
			}
			state.mu.Unlock()
			localClients.Delete(localClientID)
		}()

		for {
			_, message, err := localSocket.ReadMessage()
			if err != nil {
				fmt.Printf("[LOCAL] Socket error for %s: %v\n", localClientID, err)
				return
			}
			
			msgStr := string(message)
			var msg map[string]interface{}
			if json.Unmarshal(message, &msg) == nil {
				fmt.Printf("[PROXY] Local -> Remote (%s): %s\n", localClientID, msgStr)
			} else {
				fmt.Printf("[PROXY] Local -> Remote (%s): [Invalid JSON] %s\n", localClientID, msgStr)
			}
			
			state.mu.Lock()
			if state.remoteSocket != nil {
				err := state.remoteSocket.WriteMessage(websocket.TextMessage, message)
				if err != nil {
					fmt.Printf("[PROXY] Error handling local message: %v\n", err)
				}
			} else {
				fmt.Printf("[PROXY] Queuing message for remote...\n")
				state.messageQueue = append(state.messageQueue, message)
			}
			state.mu.Unlock()
		}
	}()
}
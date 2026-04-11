package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

// ClientState represents a connected local client
type ClientState struct {
	localSocket   *websocket.Conn
	remoteSocket  *websocket.Conn
	roomID        string
	hostID        string
	messageQueue  [][]byte
	mu            sync.Mutex
}

// Config holds application configuration
type Config struct {
	LocalPort string
	RemoteURL string
}

var (
	config       Config
	localClients sync.Map // string -> *ClientState
	nextLocalID  uint64
	upgrader     = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}
	exePath, _ = os.Executable()
	exeDir     = filepath.Dir(exePath)
	exeName    = strings.TrimSuffix(filepath.Base(exePath), filepath.Ext(exePath))
	configPath = filepath.Join(exeDir, exeName+".ini")
)

func createLocalID() string {
	id := atomic.AddUint64(&nextLocalID, 1)
	return fmt.Sprintf("L%d_%d", id, time.Now().UnixNano())
}

func loadConfig() error {
	config.LocalPort = "8080"
	config.RemoteURL = ""

	file, err := os.Open(configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		switch strings.ToUpper(key) {
		case "LOCAL_PORT":
			config.LocalPort = value
		case "REMOTE_URL":
			config.RemoteURL = value
		}
	}
	return scanner.Err()
}

func saveConfig() error {
	content := fmt.Sprintf(`# DevilBridge Local Proxy Configuration
LOCAL_PORT=%s
REMOTE_URL=%s
`, config.LocalPort, config.RemoteURL)
	return os.WriteFile(configPath, []byte(content), 0644)
}

func handleStatusPage(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if r.URL.Path == "/" {
		w.Header().Set("Content-Type", "text/html")
		
		clientsHTML := ""
		count := 0
		localClients.Range(func(key, value interface{}) bool {
			id := key.(string)
			state := value.(*ClientState)
			roomID := state.roomID
			if roomID == "" {
				roomID = "None"
			}
			isHost := "No"
			if state.hostID == id {
				isHost = "Yes"
			}
			clientsHTML += fmt.Sprintf(`
                    <div class="client">
                        <pre>ID: %s<br>Room: %s<br>Host: %s</pre>
                    </div>`, id, roomID, isHost)
			count++
			return true
		})

		if clientsHTML == "" {
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
            <meta http-equiv="refresh" content="5">
        </head>
        <body>
            <h1>DevilBridge Local Proxy</h1>
            <div class="status">
                <strong>Status:</strong> <span class="connected">● RUNNING</span><br>
                <strong>Remote Server:</strong> %s<br>
                <strong>Active Clients:</strong> %d
            </div>
            <h2>Active Connections</h2>
            <div id="clients">
                %s
            </div>
            <p style="margin-top: 2rem; font-size: 0.8rem;">Connect using: <strong>ws://localhost:%s</strong></p>
        </body>
        </html>`, config.RemoteURL, count, clientsHTML, config.LocalPort)
		
		fmt.Fprint(w, html)
	} else if r.URL.Path == "/status" {
		w.Header().Set("Content-Type", "application/json")
		
		clients := []map[string]interface{}{}
		localClients.Range(func(key, value interface{}) bool {
			id := key.(string)
			state := value.(*ClientState)
			clients = append(clients, map[string]interface{}{
				"id":     id,
				"roomId": state.roomID,
				"isHost": state.hostID == id,
			})
			return true
		})

		response := map[string]interface{}{
			"status":        "running",
			"remoteServer":  config.RemoteURL,
			"activeClients": len(clients),
			"clients":       clients,
		}
		json.NewEncoder(w).Encode(response)
	} else {
		http.NotFound(w, r)
	}
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	localSocket, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[ERROR] Failed to upgrade connection: %v", err)
		return
	}

	localClientID := createLocalID()
	log.Printf("[LOCAL] New client connected: %s", localClientID)

	state := &ClientState{
		localSocket:  localSocket,
		remoteSocket: nil,
		roomID:       "",
		hostID:       "",
		messageQueue: make([][]byte, 0),
	}
	localClients.Store(localClientID, state)

	log.Printf("[REMOTE] Connecting to remote server for %s...", localClientID)

	remoteSocket, _, err := websocket.DefaultDialer.Dial(config.RemoteURL, nil)
	if err != nil {
		log.Printf("[REMOTE] Failed to create connection for %s: %v", localClientID, err)
		localSocket.Close()
		localClients.Delete(localClientID)
		return
	}
	state.remoteSocket = remoteSocket

	// Handle remote -> local messages
	go func() {
		defer func() {
			remoteSocket.Close()
			localSocket.Close()
			localClients.Delete(localClientID)
		}()

		for {
			_, message, err := remoteSocket.ReadMessage()
			if err != nil {
				log.Printf("[REMOTE] Disconnected for client %s: %v", localClientID, err)
				
				// Send error to local client before closing
				errMsg := map[string]string{
					"type":    "ERROR",
					"message": "Connection to remote server lost",
				}
				if jsonData, err := json.Marshal(errMsg); err == nil {
					localSocket.WriteMessage(websocket.TextMessage, jsonData)
				}
				return
			}

			// Parse and track room state
			var msg map[string]interface{}
			if err := json.Unmarshal(message, &msg); err == nil {
				msgType, _ := msg["type"].(string)
				log.Printf("[PROXY] Remote -> Local (%s): %s", localClientID, msgType)

				state.mu.Lock()
				switch msgType {
				case "ROOM_CREATED":
					if code, ok := msg["code"].(string); ok {
						state.roomID = code
						state.hostID = localClientID
					}
				case "JOIN_SUCCESS":
					if code, ok := msg["code"].(string); ok {
						state.roomID = code
					}
				case "ROOM_CLOSED":
					state.roomID = ""
					state.hostID = ""
				}
				state.mu.Unlock()
			}

			if err := localSocket.WriteMessage(websocket.TextMessage, message); err != nil {
				log.Printf("[LOCAL] Error sending to client %s: %v", localClientID, err)
				return
			}
		}
	}()

	// Handle local -> remote messages
	go func() {
		defer func() {
			remoteSocket.Close()
			localSocket.Close()
			localClients.Delete(localClientID)
		}()

		for {
			_, message, err := localSocket.ReadMessage()
			if err != nil {
				log.Printf("[LOCAL] Client disconnected: %s", localClientID)
				remoteSocket.WriteMessage(websocket.CloseMessage, 
					websocket.FormatCloseMessage(websocket.CloseNormalClosure, "Local client disconnected"))
				return
			}

			// Log message type if JSON
			var msg map[string]interface{}
			if err := json.Unmarshal(message, &msg); err == nil {
				msgType, _ := msg["type"].(string)
				log.Printf("[PROXY] Local -> Remote (%s): %s", localClientID, msgType)
			} else {
				log.Printf("[PROXY] Local -> Remote (%s): [Invalid JSON]", localClientID)
			}

			state.mu.Lock()
			if err := remoteSocket.WriteMessage(websocket.TextMessage, message); err != nil {
				log.Printf("[REMOTE] Error sending from %s: %v", localClientID, err)
			}
			state.mu.Unlock()
		}
	}()
}

func runServer() {
	if config.RemoteURL == "" {
		log.Fatal("Error: REMOTE_URL configuration is required")
	}

	http.HandleFunc("/", handleStatusPage)
	http.HandleFunc("/ws", handleWebSocket)

	addr := ":" + config.LocalPort
	log.Println(strings.Repeat("=", 60))
	log.Println("DevilBridge Local Proxy Server")
	log.Println(strings.Repeat("=", 60))
	log.Printf("Local WebSocket endpoint: ws://localhost%s/ws", addr)
	log.Printf("Local HTTP endpoint: http://localhost%s", addr)
	log.Printf("Remote server: %s", config.RemoteURL)
	log.Println(strings.Repeat("=", 60))
	log.Println("\nProxy is running! Connect your game client to:")
	log.Printf("   ws://localhost%s/ws", addr)
	log.Println("\nStatus page available at:")
	log.Printf("   http://localhost%s", addr)
	log.Println(strings.Repeat("=", 60))

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}

func printUsage() {
	fmt.Printf(`DevilBridge Local Proxy - Configuration Management

Usage: %s [command]

Commands:
  (no args)          Run the proxy server
  help               Show this help message
  config             Show current configuration
  set <key> <value>  Set a configuration value
  get <key>          Get a configuration value
  delete <key>       Delete a configuration value (reset to default)
  reset              Reset all configuration to defaults

Configuration Keys:
  LOCAL_PORT         Local port for the proxy server (default: 8080)
  REMOTE_URL         Remote WebSocket server URL (required)

Examples:
  %s                                    Run the server
  %s config                             Show current config
  %s set REMOTE_URL ws://example.com    Set remote URL
  %s set LOCAL_PORT 9090                Set local port
  %s get REMOTE_URL                     Get remote URL
  %s delete LOCAL_PORT                  Reset local port to default
  %s reset                              Reset all settings

Configuration file location: %s
`, exeName, exeName, exeName, exeName, exeName, exeName, exeName, exeName, configPath)
}

func main() {
	if err := loadConfig(); err != nil {
		log.Printf("Warning: Could not load config: %v", err)
	}

	// Handle CLI commands
	if len(os.Args) > 1 {
		command := strings.ToLower(os.Args[1])
		
		switch command {
		case "help", "-h", "--help":
			printUsage()
			return
			
		case "config":
			fmt.Printf("Configuration file: %s\n\n", configPath)
			fmt.Printf("LOCAL_PORT = %s\n", config.LocalPort)
			fmt.Printf("REMOTE_URL = %s\n", config.RemoteURL)
			return
			
		case "get":
			if len(os.Args) < 3 {
				fmt.Println("Error: Missing key name")
				fmt.Println("Usage: get <key>")
				os.Exit(1)
			}
			key := strings.ToUpper(os.Args[2])
			switch key {
			case "LOCAL_PORT":
				fmt.Println(config.LocalPort)
			case "REMOTE_URL":
				fmt.Println(config.RemoteURL)
			default:
				fmt.Printf("Error: Unknown key '%s'\n", os.Args[2])
				os.Exit(1)
			}
			return
			
		case "set":
			if len(os.Args) < 4 {
				fmt.Println("Error: Missing key or value")
				fmt.Println("Usage: set <key> <value>")
				os.Exit(1)
			}
			key := strings.ToUpper(os.Args[2])
			value := strings.Join(os.Args[3:], " ")
			
			switch key {
			case "LOCAL_PORT":
				config.LocalPort = value
			case "REMOTE_URL":
				config.RemoteURL = value
			default:
				fmt.Printf("Error: Unknown key '%s'\n", os.Args[2])
				os.Exit(1)
			}
			
			if err := saveConfig(); err != nil {
				fmt.Printf("Error saving configuration: %v\n", err)
				os.Exit(1)
			}
			fmt.Printf("Configuration updated: %s = %s\n", key, value)
			return
			
		case "delete":
			if len(os.Args) < 3 {
				fmt.Println("Error: Missing key name")
				fmt.Println("Usage: delete <key>")
				os.Exit(1)
			}
			key := strings.ToUpper(os.Args[2])
			switch key {
			case "LOCAL_PORT":
				config.LocalPort = "8080"
			case "REMOTE_URL":
				config.RemoteURL = ""
			default:
				fmt.Printf("Error: Unknown key '%s'\n", os.Args[2])
				os.Exit(1)
			}
			
			if err := saveConfig(); err != nil {
				fmt.Printf("Error saving configuration: %v\n", err)
				os.Exit(1)
			}
			fmt.Printf("Configuration deleted: %s (reset to default)\n", key)
			return
			
		case "reset":
			config.LocalPort = "8080"
			config.RemoteURL = ""
			if err := saveConfig(); err != nil {
				fmt.Printf("Error saving configuration: %v\n", err)
				os.Exit(1)
			}
			fmt.Println("Configuration reset to defaults")
			return
			
		default:
			fmt.Printf("Error: Unknown command '%s'\n", command)
			fmt.Printf("Run '%s help' for usage information\n", exeName)
			os.Exit(1)
		}
	}

	// Run server (no arguments)
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt)

	go runServer()

	<-sigChan
	log.Println("\nShutting down proxy...")
	
	// Close all connections
	localClients.Range(func(key, value interface{}) bool {
		state := value.(*ClientState)
		if state.remoteSocket != nil {
			state.remoteSocket.Close()
		}
		if state.localSocket != nil {
			state.localSocket.Close()
		}
		return true
	})
	
	log.Println("Proxy stopped.")
}
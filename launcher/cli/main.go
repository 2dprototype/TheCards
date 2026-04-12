package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
)

func getExeDir() string {
	exePath, err := os.Executable()
	if err != nil {
		pwd, _ := os.Getwd()
		return pwd
	}
	// If running via `go run`, Executable path is in a temp dir.
	// Fallback to working directory if exe is deeply nested in /tmp/
	if strings.Contains(exePath, "Temp") || strings.Contains(exePath, "tmp") {
		pwd, _ := os.Getwd()
		return pwd
	}
	return filepath.Dir(exePath)
}

func loadEnv(envPath string) map[string]string {
	env := make(map[string]string)
	file, err := os.Open(envPath)
	if err != nil {
		return env
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
			k := strings.TrimSpace(parts[0])
			v := strings.TrimSpace(parts[1])
			v = strings.Trim(v, `"'`)
			env[k] = v
		}
	}
	return env
}

func saveEnv(envPath string, env map[string]string) {
	file, err := os.Create(envPath)
	if err != nil {
		fmt.Printf("Warning: Could not save .env file: %v\n", err)
		return
	}
	defer file.Close()
	for k, v := range env {
		file.WriteString(fmt.Sprintf("%s=%s\n", k, v))
	}
	fmt.Printf("Saved settings to %s\n", envPath)
}

func main() {
	exeDir := getExeDir()
	envPath := filepath.Join(exeDir, ".env")

	flagRemoteURL := flag.String("remote-url", "", "Remote server URL")
	flagPort := flag.String("port", "", "Local proxy port")
	flag.Parse()

	env := loadEnv(envPath)

	remoteURL := *flagRemoteURL
	if remoteURL == "" {
		if val, exists := env["REMOTE_URL"]; exists {
			remoteURL = val
		}
	}

	port := *flagPort
	if port == "" {
		if val, exists := env["LOCAL_PORT"]; exists {
			port = val
		}
	}

	needsSave := false
	reader := bufio.NewReader(os.Stdin)

	if remoteURL == "" {
		fmt.Print("Enter Remote Server URL (e.g., wss://devilbridge.onrender.com): ")
		input, _ := reader.ReadString('\n')
		remoteURL = strings.TrimSpace(input)
		env["REMOTE_URL"] = remoteURL
		needsSave = true
	}

	if port == "" {
		fmt.Print("Enter Local Proxy Port (default: 8080): ")
		input, _ := reader.ReadString('\n')
		port = strings.TrimSpace(input)
		if port == "" {
			port = "8080"
		}
		env["LOCAL_PORT"] = port
		needsSave = true
	}

	if remoteURL == "" {
		fmt.Println("Error: Remote URL cannot be empty. Exiting.")
		os.Exit(1)
	}

	if needsSave {
		saveEnv(envPath, env)
	}

	fmt.Println(strings.Repeat("=", 60))
	fmt.Println("DevilBridge Game Launcher")
	fmt.Println(strings.Repeat("=", 60))
	fmt.Printf("Remote URL: %s\n", remoteURL)
	fmt.Printf("Local Port: %s\n", port)
	fmt.Println(strings.Repeat("=", 60))

	// Setup context for orchestration
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	// Look for proxy.exe in exeDir
	var proxyCmd *exec.Cmd
	proxyPath := filepath.Join(exeDir, "proxy.exe")
	
	if _, err := os.Stat(proxyPath); err == nil {
		fmt.Println(">> Found proxy.exe, starting local proxy...")
		proxyCmd = exec.CommandContext(ctx, proxyPath, "-remote-url", remoteURL, "-port", port)
	} else {
		// Check for proxy without .exe extension (for non-Windows systems)
		proxyPathNoExt := filepath.Join(exeDir, "proxy")
		if _, err := os.Stat(proxyPathNoExt); err == nil {
			fmt.Println(">> Found proxy executable, starting local proxy...")
			proxyCmd = exec.CommandContext(ctx, proxyPathNoExt, "-remote-url", remoteURL, "-port", port)
		} else {
			fmt.Println("Error: proxy.exe not found in", exeDir)
			fmt.Println("Please ensure proxy.exe is present in the application directory.")
			os.Exit(1)
		}
	}
	
	proxyCmd.Stdout = os.Stdout
	proxyCmd.Stderr = os.Stderr

	fmt.Println(">> Starting Local Proxy...")
	if err := proxyCmd.Start(); err != nil {
		log.Fatalf("Failed to start proxy: %v", err)
	}

	// Wait briefly to ensure proxy is up
	go func() {
		err := proxyCmd.Wait()
		if err != nil && ctx.Err() == nil {
			fmt.Printf(">> Proxy exited unexpectedly: %v\n", err)
		}
		// If proxy dies, terminate everything
		cancel()
	}()

	fmt.Println(">> Launching Game Client...")
	gamePath := filepath.Join(exeDir, "bridge.exe")
	
	// Check for bridge.exe
	if _, err := os.Stat(gamePath); err != nil {
		// Try without .exe extension for non-Windows systems
		gamePathNoExt := filepath.Join(exeDir, "bridge")
		if _, err := os.Stat(gamePathNoExt); err == nil {
			gamePath = gamePathNoExt
		} else {
			fmt.Println("Error: bridge.exe not found in", exeDir)
			fmt.Println("Please ensure bridge.exe is present in the application directory.")
			cancel()
			os.Exit(1)
		}
	}
	
	gameURL := fmt.Sprintf("ws://127.0.0.1:%s", port)
	gameCmd := exec.CommandContext(ctx, gamePath, "--server-uri", gameURL)
	gameCmd.Stdout = os.Stdout
	gameCmd.Stderr = os.Stderr

	if err := gameCmd.Start(); err != nil {
		fmt.Printf("Failed to start game client: %v\n", err)
		cancel()
	}

	// Main loop: wait for Game exit or Interrupt
	go func() {
		err := gameCmd.Wait()
		if err != nil && ctx.Err() == nil {
			fmt.Printf(">> Game closed with error: %v\n", err)
		} else {
			fmt.Println(">> Game closed successfully.")
		}
		// When game finishes, terminate proxy via context cancel
		cancel()
	}()

	select {
	case <-ctx.Done():
		fmt.Println(">> Shutting down services...")
	case <-sigChan:
		fmt.Println("\n>> Received interrupt, shutting down...")
		cancel()
	}

	fmt.Println(">> Launcher exited.")
}
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

	"github.com/gonutz/wui/v2"
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

func saveEnv(envPath string, env map[string]string) error {
	file, err := os.Create(envPath)
	if err != nil {
		return err
	}
	defer file.Close()
	for k, v := range env {
		file.WriteString(fmt.Sprintf("%s=%s\n", k, v))
	}
	return nil
}

func showConfigWindow(exeDir string) (string, string, bool) {
	envPath := filepath.Join(exeDir, ".env")
	env := loadEnv(envPath)
	
	remoteURL := env["REMOTE_URL"]
	port := env["LOCAL_PORT"]
	if port == "" {
		port = "8080"
	}
	
	applied := false
	
	windowFont, _ := wui.NewFont(wui.FontDesc{
		Name:   "Tahoma",
		Height: -11,
	})

	window := wui.NewWindow()
	window.SetFont(windowFont)
	window.SetInnerBounds(270, 100, 504, 308)
	window.SetTitle("Bridge Launcher")
	window.SetHasMaxButton(false)
	window.SetHasMinButton(false)

	editRemoteURL := wui.NewEditLine()
	editRemoteURL.SetBounds(32, 86, 439, 23)
	editRemoteURL.SetText(remoteURL)
	window.Add(editRemoteURL)

	labelRemote := wui.NewLabel()
	labelRemote.SetBounds(33, 65, 151, 12)
	labelRemote.SetText("Remote URL")
	window.Add(labelRemote)

	editPort := wui.NewEditLine()
	editPort.SetBounds(31, 152, 438, 22)
	editPort.SetText(port)
	window.Add(editPort)

	labelPort := wui.NewLabel()
	labelPort.SetBounds(31, 130, 150, 20)
	labelPort.SetText("Port")
	window.Add(labelPort)

	buttonApply := wui.NewButton()
	buttonApply.SetBounds(29, 197, 85, 25)
	buttonApply.SetText("Apply")
	window.Add(buttonApply)

	labelTitleFont, _ := wui.NewFont(wui.FontDesc{
		Name:   "Tahoma",
		Height: -20,
	})

	labelTitle := wui.NewLabel()
	labelTitle.SetFont(labelTitleFont)
	labelTitle.SetBounds(30, 21, 168, 29)
	labelTitle.SetText("Bridge Launcher")
	window.Add(labelTitle)

	labelInfo := wui.NewLabel()
	labelInfo.SetBounds(30, 257, 392, 28)
	labelInfo.SetText("Your REMOTE_URL and PORT data will be stored in .env file")
	window.Add(labelInfo)

	// progressBar := wui.NewProgressBar()
	// progressBar.SetBounds(71, 245, 362, 8)
	// progressBar.SetValue(0)
	// progressBar.SetVisible(false)
	// window.Add(progressBar)

	buttonApply.SetOnClick(func() {
		newRemoteURL := strings.TrimSpace(editRemoteURL.Text())
		newPort := strings.TrimSpace(editPort.Text())
		
		if newRemoteURL == "" {
			labelInfo.SetText("Error: Remote URL cannot be empty!")
			return
		}
		
		if newPort == "" {
			newPort = "8080"
		}
		
		env["REMOTE_URL"] = newRemoteURL
		env["LOCAL_PORT"] = newPort
		
		if err := saveEnv(envPath, env); err != nil {
			labelInfo.SetText(fmt.Sprintf("Error saving config: %v", err))
			return
		}
		
		remoteURL = newRemoteURL
		port = newPort
		applied = true
		
		labelInfo.SetText("Configuration saved successfully!")
		
		// Close window after a short delay
		go func() {
			window.Close()
		}()
	})

	window.SetOnClose(func() {
		// Just close, nothing special
	})

	window.Show()
	
	return remoteURL, port, applied
}

func runLauncher(exeDir, remoteURL, port string) {
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

func main() {
	// Parse command line flags
	flagConfig := flag.Bool("config", false, "Show configuration window")
	flagRemoteURL := flag.String("remote-url", "", "Remote server URL")
	flagPort := flag.String("port", "", "Local proxy port")
	flag.Parse()

	exeDir := getExeDir()
	envPath := filepath.Join(exeDir, ".env")
	
	// Check if we need to show config window
	_, envErr := os.Stat(envPath)
	needConfig := envErr != nil || *flagConfig
	
	var remoteURL, port string
	
	if needConfig {
		// Show GUI configuration window
		remoteURL, port, _ = showConfigWindow(exeDir)
		
		// If env didn't exist and user didn't configure, exit
		if remoteURL == "" && envErr != nil {
			fmt.Println("No configuration provided. Exiting.")
			os.Exit(0)
		}
	} else {
		// Load from .env file
		env := loadEnv(envPath)
		remoteURL = *flagRemoteURL
		if remoteURL == "" {
			if val, exists := env["REMOTE_URL"]; exists {
				remoteURL = val
			}
		}
		port = *flagPort
		if port == "" {
			if val, exists := env["LOCAL_PORT"]; exists {
				port = val
			}
		}
	}
	
	// Validate configuration
	if remoteURL == "" {
		// If no remote URL, show config window even if .env exists
		remoteURL, port, _ = showConfigWindow(exeDir)
		if remoteURL == "" {
			fmt.Println("Error: Remote URL cannot be empty. Exiting.")
			os.Exit(1)
		}
	}
	
	if port == "" {
		port = "8080"
		// Save the default port
		env := loadEnv(envPath)
		env["LOCAL_PORT"] = port
		saveEnv(envPath, env)
	}
	
	// Hide console window on Windows (optional - uncomment if needed)
	// go func() {
	// 	user32 := syscall.NewLazyDLL("user32.dll")
	// 	procShowWindow := user32.NewProc("ShowWindow")
	// 	console := syscall.NewLazyDLL("kernel32.dll").NewProc("GetConsoleWindow")
	// 	hwnd, _, _ := console.Call()
	// 	if hwnd != 0 {
	// 		procShowWindow.Call(hwnd, 0) // SW_HIDE
	// 	}
	// }()
	
	// Run the launcher
	runLauncher(exeDir, remoteURL, port)
}
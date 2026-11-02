//go:build windows

package main

import (
	"context"
	"os/exec"
	"syscall"
)

// Tauri-generated NSIS /S is the supported unattended installer entry point.
// Do not rewrite the registry, Windows uninstall metadata, or install directory.
func runOfficialNSIS(ctx context.Context, path string) error {
	command:=exec.CommandContext(ctx,path,"/S")
	command.SysProcAttr=&syscall.SysProcAttr{HideWindow:true}
	return command.Run()
}

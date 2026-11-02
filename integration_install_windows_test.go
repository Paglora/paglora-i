//go:build windows && integration

package main

import (
	"context"
	"os"
	"testing"
	"time"
)

// Runs an actual embedded Paglora NSIS package on an isolated Windows CI
// runner. Not run by ordinary go test. Requires explicit environment opt-in.
func TestRealWindowsNSISInstall(t *testing.T) {
	if os.Getenv("PAGLORA_EPHEMERAL_WINDOWS_CI") != "yes" ||
		os.Getenv("GITHUB_ACTIONS") != "true" {
		t.Skip("Real silent install is restricted to explicitly opted-in GitHub Actions runners")
	}
	app := NewApp(payloadAssets)
	if status := app.GetStatus(); status.Phase != "ready" {
		t.Fatalf("Real Paglora installer not ready: %+v", status)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	app.startup(ctx)
	started, err := app.BeginInstall()
	if err != nil || !started {
		t.Fatalf("Could not start real NSIS install: started=%t, error=%v", started, err)
	}
	timer := time.NewTicker(250 * time.Millisecond)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			t.Fatalf("Real NSIS installer timed out: %+v", app.GetStatus())
		case <-timer.C:
			status := app.GetStatus()
			switch status.Phase {
			case "complete":
				t.Logf("Paglora NSIS completed: %s", status.Message)
				return
			case "error":
				t.Fatalf("Paglora NSIS failed: %s", status.Message)
			}
		}
	}
}

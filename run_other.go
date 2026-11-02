//go:build !windows

package main

import (
	"context"
	"errors"
)

func runOfficialNSIS(_ context.Context,_ string)error{
	return errors.New("Paglora Windows setup can run only on Windows")
}

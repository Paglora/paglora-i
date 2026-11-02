package installer

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"regexp"
	"strings"
)

var ErrNotPackaged = errors.New("No verified Paglora package is embedded. Build with scripts/package.ps1.")

type Manifest struct {
	Version  string `json:"version"`
	FileName string `json:"fileName"`
	SHA256   string `json:"sha256"`
	Size     int64  `json:"size"`
}

var versionPattern = regexp.MustCompile(`^[0-9]+.[0-9]+.[0-9]+$`)

// Validate rejects payload path traversal, release/version mismatches and unpinned bytes.
// This SHA-256 check is an integrity check; it does not replace Authenticode
// or the separate Tauri updater's signature validation.
func (m Manifest) Validate() error {
	if m.Version == "" && m.FileName == "" && m.SHA256 == "" && m.Size == 0 {
		return ErrNotPackaged
	}
	if !versionPattern.MatchString(m.Version) {
		return errors.New("Invalid embedded Paglora version")
	}
	expected := "Paglora_" + m.Version + "_x64-setup.exe"
	if m.FileName != expected || path.Base(m.FileName) != m.FileName ||
		strings.ContainsAny(m.FileName, "/\") {
		return errors.New("Embedded package name or version does not match Paglora NSIS")
	}
	raw, err := hex.DecodeString(m.SHA256)
	if err != nil || len(raw) != sha256.Size || m.SHA256 != strings.ToLower(m.SHA256) {
		return errors.New("Embedded package SHA-256 is invalid")
	}
	if m.Size < 1024 || m.Size > 500*1024*1024 {
		return errors.New("Embedded package size is out of bounds")
	}
	return nil
}

func ReadManifest(assets fs.FS) (Manifest, error) {
	var m Manifest
	file, err := assets.Open("payload/manifest.json")
	if err != nil {
		return m, fmt.Errorf("Cannot open installer manifest: %w", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, 4096))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&m); err != nil {
		return m, fmt.Errorf("Invalid installer manifest: %w", err)
	}
	return m, m.Validate()
}

// ExtractVerified writes a new private temporary file, verifies size + checksum
// before executing, and refuses symlink/path redirection. Caller removes dir.
func ExtractVerified(assets fs.FS, m Manifest, destDir string) (string, error) {
	if err := m.Validate(); err != nil { return "", err }
	input, err := assets.Open("payload/" + m.FileName)
	if err != nil { return "", fmt.Errorf("Missing embedded Paglora NSIS payload: %w", err) }
	defer input.Close()

	filename := path.Join(destDir, m.FileName)
	output, err := os.OpenFile(filename, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil { return "", err }
	hash := sha256.New()
	n, copyErr := io.Copy(io.MultiWriter(output, hash), io.LimitReader(input, m.Size+1))
	closeErr := output.Close()
	if copyErr != nil || closeErr != nil || n != m.Size ||
		hex.EncodeToString(hash.Sum(nil)) != m.SHA256 {
		_ = os.Remove(filename)
		return "", errors.New("Bundled installer failed size/SHA-256 verification")
	}
	return filename, nil
}

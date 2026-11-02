package installer

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"
)

func sample() (fstest.MapFS, Manifest) {
	data := []byte(strings.Repeat("trusted-bundle-", 100))
	sum := sha256.Sum256(data)
	m := Manifest{
		Version:"0.2.0", FileName:"Paglora_0.2.0_x64-setup.exe",
		SHA256:hex.EncodeToString(sum[:]), Size:int64(len(data)),
	}
	return fstest.MapFS{"payload/"+m.FileName:&fstest.MapFile{Data:data}},m
}
func TestValidBundleExtractsExactBytes(t *testing.T) {
	files,m:=sample()
	dir:=t.TempDir()
	path,err:=ExtractVerified(files,m,dir)
	if err!=nil { t.Fatal(err) }
	s,err:=os.ReadFile(path)
	if err!=nil { t.Fatal(err) }
	if int64(len(s))!=m.Size || filepath.Base(path)!=m.FileName {t.Fatal("incorrect extracted payload")}
	if _,err=ExtractVerified(files,m,dir);err==nil {t.Fatal("must not overwrite existing payload")}
}
func TestRejectsMismatchedHashAndSize(t *testing.T) {
	files,m:=sample()
	m.SHA256=strings.Repeat("0",64)
	if _,err:=ExtractVerified(files,m,t.TempDir());err==nil {t.Fatal("hash mismatch accepted")}
	_,m=sample()
	m.Size++
	if _,err:=ExtractVerified(files,m,t.TempDir());err==nil {t.Fatal("length mismatch accepted")}
}
func TestUnsafeNamesAndNoPayload(t *testing.T){
	_,m:=sample()
	for _,name:=range []string{"../app.exe","C:\\evil.exe","Paglora_0.3.0_x64-setup.exe","/tmp/evil","Paglora_0.2.0_x64-setup.exe/../x"}{
		m.FileName=name
		if m.Validate()==nil {t.Fatalf("accepted unsafe payload name %q",name)}
	}
	if err:=(Manifest{}).Validate();!errors.Is(err,ErrNotPackaged){t.Fatalf("expected NotPackaged, got %v",err)}
}
func TestNoPayloadManifest(t *testing.T) {
	f:=fstest.MapFS{"payload/manifest.json":&fstest.MapFile{Data:[]byte(`{"version":"","fileName":"","sha256":"","size":0}`)}}
	_,err:=ReadManifest(fs.FS(f))
	if !errors.Is(err,ErrNotPackaged){t.Fatalf("expected no package, got %v",err)}
}

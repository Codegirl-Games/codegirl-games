package appspec

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolveDirectoryManifest(t *testing.T) {
	directory := t.TempDir()
	executable := filepath.Join(directory, "game")
	if err := os.WriteFile(executable, []byte("binary"), 0o755); err != nil {
		t.Fatal(err)
	}
	manifest := `{"command":"game","args":["--demo"],"window_title":"Demo"}`
	if err := os.WriteFile(filepath.Join(directory, "agentbox.json"), []byte(manifest), 0o644); err != nil {
		t.Fatal(err)
	}

	command, err := Resolve(directory)
	if err != nil {
		t.Fatal(err)
	}
	if command.Path != executable || command.WindowTitle != "Demo" ||
		len(command.Args) != 1 || command.Args[0] != "--demo" {
		t.Fatalf("command = %#v", command)
	}
}

package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
)

// findProjectRoot lets commands work from any directory inside the Agentbox
// module. The module declaration is a stronger marker than a directory name.
func findProjectRoot() (string, error) {
	currentDirectory, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		goModule, readErr := os.ReadFile(filepath.Join(currentDirectory, "go.mod"))
		if readErr == nil && bytes.Contains(goModule, []byte("module agentbox")) {
			return currentDirectory, nil
		}
		parentDirectory := filepath.Dir(currentDirectory)
		if parentDirectory == currentDirectory {
			return "", errors.New("run agentbox from inside its module directory")
		}
		currentDirectory = parentDirectory
	}
}

package appspec

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"agentbox/internal/environment"
)

type manifest struct {
	Command     string            `json:"command"`
	Args        []string          `json:"args"`
	Env         map[string]string `json:"env"`
	WindowTitle string            `json:"window_title"`
}

func Resolve(path string) (environment.Command, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return environment.Command{}, fmt.Errorf("resolve application path: %w", err)
	}
	info, err := os.Stat(absolute)
	if err != nil {
		return environment.Command{}, fmt.Errorf("inspect application path: %w", err)
	}
	if !info.IsDir() {
		if !info.Mode().IsRegular() {
			return environment.Command{}, errors.New("application must be a regular executable file")
		}
		return environment.Command{Path: absolute}, nil
	}

	data, err := os.ReadFile(filepath.Join(absolute, "agentbox.json"))
	if err != nil {
		return environment.Command{}, fmt.Errorf("read directory manifest agentbox.json: %w", err)
	}
	var config manifest
	if err := json.Unmarshal(data, &config); err != nil {
		return environment.Command{}, fmt.Errorf("parse agentbox.json: %w", err)
	}
	if config.Command == "" {
		return environment.Command{}, errors.New("agentbox.json requires command")
	}
	commandPath := config.Command
	if !filepath.IsAbs(commandPath) {
		commandPath = filepath.Join(absolute, commandPath)
	}
	commandInfo, err := os.Stat(commandPath)
	if err != nil {
		return environment.Command{}, fmt.Errorf("inspect manifest command: %w", err)
	}
	if !commandInfo.Mode().IsRegular() {
		return environment.Command{}, errors.New("manifest command must be a regular executable file")
	}
	return environment.Command{
		Path:        commandPath,
		Args:        config.Args,
		Env:         config.Env,
		WindowTitle: config.WindowTitle,
	}, nil
}

package dockerx11

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"agentbox/internal/environment"
)

const imageName = "agentbox-runtime:local"

type Config struct {
	ProjectRoot string
	RunID       string
	Output      io.Writer
}

type Environment struct {
	config        Config
	containerName string
	created       bool
	stopped       bool
	mu            sync.Mutex
}

func New(config Config) *Environment {
	return &Environment{
		config:        config,
		containerName: "agentbox-run-" + config.RunID,
	}
}

func (e *Environment) Start(ctx context.Context) error {
	if e.config.Output == nil {
		e.config.Output = io.Discard
	}
	if _, err := e.docker(ctx, "version", "--format", "{{.Server.Version}}"); err != nil {
		return fmt.Errorf("Docker is required and the daemon must be accessible: %w", err)
	}
	fmt.Fprintln(e.config.Output, "Creating environment...")
	if err := e.dockerStream(ctx, "build", "-q", "-t", imageName, "-f",
		filepath.Join(e.config.ProjectRoot, "environment", "Dockerfile"), e.config.ProjectRoot); err != nil {
		return fmt.Errorf("build environment image: %w", err)
	}
	_, err := e.docker(ctx,
		"create",
		"--name", e.containerName,
		"--init",
		"--network=none",
		"--read-only",
		"--tmpfs=/tmp:rw,nosuid,nodev,size=128m",
		"--cap-drop=ALL",
		"--security-opt=no-new-privileges",
		"--pids-limit=128",
		"--memory=512m",
		"--cpus=1",
		imageName,
	)
	if err != nil {
		return fmt.Errorf("create environment: %w", err)
	}
	e.created = true
	if _, err := e.docker(ctx, "start", e.containerName); err != nil {
		return fmt.Errorf("start environment: %w", err)
	}
	if err := e.waitFor(ctx, 10*time.Second, func() bool {
		_, readyErr := e.docker(ctx, "exec", e.containerName, "test", "-f", "/tmp/agentbox-ready")
		return readyErr == nil
	}); err != nil {
		return fmt.Errorf("wait for graphical environment: %w", err)
	}
	return nil
}

func (e *Environment) Launch(ctx context.Context, command environment.Command) error {
	fmt.Fprintln(e.config.Output, "Uploading build...")
	file, err := os.Open(command.Path)
	if err != nil {
		return fmt.Errorf("open application: %w", err)
	}
	defer file.Close()

	stage := exec.CommandContext(ctx, "docker", "exec", "-i", e.containerName, "sh", "-c",
		"cat > /tmp/application && chmod 0500 /tmp/application")
	stage.Stdin = file
	if output, err := stage.CombinedOutput(); err != nil {
		return fmt.Errorf("stage application: %w: %s", err, strings.TrimSpace(string(output)))
	}

	fmt.Fprintln(e.config.Output, "Launching application...")
	args := []string{"exec", "-d"}
	for key, value := range command.Env {
		args = append(args, "-e", key+"="+value)
	}
	args = append(args, e.containerName, "sh", "-c")
	parts := []string{"exec", "/tmp/application"}
	for _, arg := range command.Args {
		parts = append(parts, shellQuote(arg))
	}
	parts = append(parts, ">/tmp/stdout.log", "2>/tmp/stderr.log")
	args = append(args, strings.Join(parts, " "))
	if _, err := e.docker(ctx, args...); err != nil {
		return fmt.Errorf("launch application: %w", err)
	}

	if command.WindowTitle != "" {
		var windowID string
		if err := e.waitFor(ctx, 10*time.Second, func() bool {
			output, searchErr := e.docker(ctx, "exec", e.containerName, "xdotool",
				"search", "--name", command.WindowTitle)
			if searchErr != nil {
				return false
			}
			windowID = strings.TrimSpace(strings.Split(string(output), "\n")[0])
			return windowID != ""
		}); err != nil {
			return fmt.Errorf("wait for application window %q: %w", command.WindowTitle, err)
		}
		if _, err := e.docker(ctx, "exec", e.containerName, "xdotool",
			"windowactivate", "--sync", windowID); err != nil {
			return fmt.Errorf("focus application window: %w", err)
		}
	} else {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(500 * time.Millisecond):
		}
	}
	return nil
}

func (e *Environment) Screenshot(ctx context.Context) ([]byte, error) {
	if _, err := e.docker(ctx, "exec", e.containerName, "scrot", "-o", "/tmp/screenshot.png"); err != nil {
		return nil, fmt.Errorf("capture screenshot: %w", err)
	}
	data, err := e.docker(ctx, "exec", e.containerName, "cat", "/tmp/screenshot.png")
	if err != nil {
		return nil, fmt.Errorf("extract screenshot: %w", err)
	}
	return data, nil
}

func (e *Environment) SendInput(ctx context.Context, action environment.InputAction) error {
	var args []string
	switch action.Type {
	case environment.KeyDown:
		if action.Key == "" {
			return errors.New("key_down requires key")
		}
		args = []string{"keydown", action.Key}
	case environment.KeyUp:
		if action.Key == "" {
			return errors.New("key_up requires key")
		}
		args = []string{"keyup", action.Key}
	case environment.MouseMove:
		args = []string{"mousemove", strconv.Itoa(action.X), strconv.Itoa(action.Y)}
	case environment.MouseDown:
		args = []string{"mousedown", strconv.Itoa(action.Button)}
	case environment.MouseUp:
		args = []string{"mouseup", strconv.Itoa(action.Button)}
	case environment.Wait:
		if action.Duration < 0 {
			return errors.New("wait duration cannot be negative")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(action.Duration):
			return nil
		}
	default:
		return fmt.Errorf("unsupported input action %q", action.Type)
	}
	_, err := e.docker(ctx, append([]string{"exec", e.containerName, "xdotool"}, args...)...)
	if err != nil {
		return fmt.Errorf("send %s: %w", action.Type, err)
	}
	return nil
}

func (e *Environment) Logs(ctx context.Context) ([]environment.LogEntry, error) {
	var entries []environment.LogEntry
	for _, stream := range []string{"stdout", "stderr"} {
		data, err := e.docker(ctx, "exec", e.containerName, "cat", "/tmp/"+stream+".log")
		if err != nil {
			continue
		}
		if len(data) > 0 {
			entries = append(entries, environment.LogEntry{
				Stream: stream, Message: string(data), Time: time.Now().UTC(),
			})
		}
	}
	return entries, nil
}

func (e *Environment) Stop(ctx context.Context) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.created || e.stopped {
		return nil
	}
	e.stopped = true
	fmt.Fprintln(e.config.Output, "Shutting environment down...")
	_, stopErr := e.docker(ctx, "stop", "--time=3", e.containerName)
	_, removeErr := e.docker(ctx, "rm", "-f", e.containerName)
	if stopErr != nil {
		return fmt.Errorf("stop environment: %w", stopErr)
	}
	if removeErr != nil {
		return fmt.Errorf("remove environment: %w", removeErr)
	}
	return nil
}

func (e *Environment) waitFor(ctx context.Context, timeout time.Duration, check func() bool) error {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		if check() {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-timer.C:
			return errors.New("timed out")
		case <-ticker.C:
		}
	}
}

func (e *Environment) docker(ctx context.Context, args ...string) ([]byte, error) {
	command := exec.CommandContext(ctx, "docker", args...)
	output, err := command.CombinedOutput()
	if err != nil {
		return output, fmt.Errorf("docker %s: %w: %s", args[0], err, strings.TrimSpace(string(output)))
	}
	return output, nil
}

func (e *Environment) dockerStream(ctx context.Context, args ...string) error {
	command := exec.CommandContext(ctx, "docker", args...)
	command.Stdout = e.config.Output
	command.Stderr = e.config.Output
	return command.Run()
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

var _ environment.Environment = (*Environment)(nil)

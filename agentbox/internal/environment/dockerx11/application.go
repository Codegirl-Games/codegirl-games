package dockerx11

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"agentbox/internal/environment"
)

const stagedApplicationPath = "/tmp/application"

func (environmentBackend *Environment) Launch(
	ctx context.Context,
	application environment.Command,
) error {
	fmt.Fprintln(environmentBackend.config.Output, "Uploading build...")
	executable, err := os.Open(application.Path)
	if err != nil {
		return fmt.Errorf("open application: %w", err)
	}
	defer executable.Close()

	// Stream instead of bind-mounting the developer's directory. The container
	// sees only the requested executable, and the copy disappears at teardown.
	stageCommand := exec.CommandContext(
		ctx,
		"docker",
		"exec",
		"-i",
		environmentBackend.containerName,
		"sh",
		"-c",
		"cat > "+stagedApplicationPath+" && chmod 0500 "+stagedApplicationPath,
	)
	stageCommand.Stdin = executable
	if output, err := stageCommand.CombinedOutput(); err != nil {
		return fmt.Errorf(
			"stage application: %w: %s",
			err,
			strings.TrimSpace(string(output)),
		)
	}

	fmt.Fprintln(environmentBackend.config.Output, "Launching application...")
	dockerArguments := []string{"exec", "-d"}
	for variableName, variableValue := range application.Env {
		dockerArguments = append(
			dockerArguments,
			"-e",
			variableName+"="+variableValue,
		)
	}
	dockerArguments = append(
		dockerArguments,
		environmentBackend.containerName,
		"sh",
		"-c",
	)
	shellCommand := []string{"exec", stagedApplicationPath}
	for _, applicationArgument := range application.Args {
		shellCommand = append(shellCommand, shellQuote(applicationArgument))
	}
	shellCommand = append(
		shellCommand,
		">/tmp/stdout.log",
		"2>/tmp/stderr.log",
	)
	dockerArguments = append(dockerArguments, strings.Join(shellCommand, " "))
	if _, err := environmentBackend.runDocker(ctx, dockerArguments...); err != nil {
		return fmt.Errorf("launch application: %w", err)
	}

	return environmentBackend.focusApplicationWindow(ctx, application.WindowTitle)
}

func (environmentBackend *Environment) focusApplicationWindow(
	ctx context.Context,
	windowTitle string,
) error {
	if windowTitle == "" {
		// Applications without a title cannot be searched reliably. Give the
		// process a brief startup window before the first screenshot.
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(500 * time.Millisecond):
			return nil
		}
	}

	var windowID string
	if err := waitFor(ctx, 10*time.Second, func() bool {
		output, searchErr := environmentBackend.runDocker(
			ctx,
			"exec",
			environmentBackend.containerName,
			"xdotool",
			"search",
			"--name",
			windowTitle,
		)
		if searchErr != nil {
			return false
		}
		windowID = strings.TrimSpace(strings.Split(string(output), "\n")[0])
		return windowID != ""
	}); err != nil {
		return fmt.Errorf("wait for application window %q: %w", windowTitle, err)
	}
	if _, err := environmentBackend.runDocker(
		ctx,
		"exec",
		environmentBackend.containerName,
		"xdotool",
		"windowactivate",
		"--sync",
		windowID,
	); err != nil {
		return fmt.Errorf("focus application window: %w", err)
	}
	return nil
}

func (environmentBackend *Environment) Screenshot(ctx context.Context) ([]byte, error) {
	const screenshotPath = "/tmp/screenshot.png"
	if _, err := environmentBackend.runDocker(
		ctx,
		"exec",
		environmentBackend.containerName,
		"scrot",
		"-o",
		screenshotPath,
	); err != nil {
		return nil, fmt.Errorf("capture screenshot: %w", err)
	}
	screenshot, err := environmentBackend.runDocker(
		ctx,
		"exec",
		environmentBackend.containerName,
		"cat",
		screenshotPath,
	)
	if err != nil {
		return nil, fmt.Errorf("extract screenshot: %w", err)
	}
	return screenshot, nil
}

func (environmentBackend *Environment) Logs(
	ctx context.Context,
) ([]environment.LogEntry, error) {
	var logEntries []environment.LogEntry
	for _, streamName := range []string{"stdout", "stderr"} {
		logContents, err := environmentBackend.runDocker(
			ctx,
			"exec",
			environmentBackend.containerName,
			"cat",
			"/tmp/"+streamName+".log",
		)
		if err != nil || len(logContents) == 0 {
			continue
		}
		logEntries = append(logEntries, environment.LogEntry{
			Stream:  streamName,
			Message: string(logContents),
			Time:    time.Now().UTC(),
		})
	}
	return logEntries, nil
}

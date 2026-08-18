package dockerx11

import (
	"context"
	"fmt"
	"io"
	"path/filepath"
	"time"
)

func (environmentBackend *Environment) Start(ctx context.Context) error {
	if environmentBackend.config.Output == nil {
		environmentBackend.config.Output = io.Discard
	}
	if _, err := environmentBackend.runDocker(
		ctx,
		"version",
		"--format",
		"{{.Server.Version}}",
	); err != nil {
		return fmt.Errorf("Docker is required and the daemon must be accessible: %w", err)
	}

	fmt.Fprintln(environmentBackend.config.Output, "Creating environment...")
	dockerfilePath := filepath.Join(
		environmentBackend.config.ProjectRoot,
		"environment",
		"Dockerfile",
	)
	if err := environmentBackend.streamDockerOutput(
		ctx,
		"build",
		"-q",
		"-t",
		runtimeImageName,
		"-f",
		dockerfilePath,
		environmentBackend.config.ProjectRoot,
	); err != nil {
		return fmt.Errorf("build environment image: %w", err)
	}

	// These restrictions reduce accidental damage. They are defense in depth,
	// not a safe boundary for hostile customer code; see docs/architecture.md.
	_, err := environmentBackend.runDocker(
		ctx,
		"create",
		"--name", environmentBackend.containerName,
		"--init",
		"--network=none",
		"--read-only",
		"--tmpfs=/tmp:rw,exec,nosuid,nodev,size=128m",
		"--cap-drop=ALL",
		"--security-opt=no-new-privileges",
		"--pids-limit=128",
		"--memory=512m",
		"--cpus=1",
		runtimeImageName,
	)
	if err != nil {
		return fmt.Errorf("create environment: %w", err)
	}
	environmentBackend.containerCreated = true

	if _, err := environmentBackend.runDocker(
		ctx,
		"start",
		environmentBackend.containerName,
	); err != nil {
		return fmt.Errorf("start environment: %w", err)
	}
	// entrypoint.sh creates this file only after both Xvfb and Openbox accept
	// requests. It is the readiness handshake between host and container.
	if err := waitFor(ctx, 10*time.Second, func() bool {
		_, readyErr := environmentBackend.runDocker(
			ctx,
			"exec",
			environmentBackend.containerName,
			"test",
			"-f",
			"/tmp/agentbox-ready",
		)
		return readyErr == nil
	}); err != nil {
		return fmt.Errorf("wait for graphical environment: %w", err)
	}
	return nil
}

// Stop is idempotent because both normal completion and deferred cleanup may
// try to tear down the same environment.
func (environmentBackend *Environment) Stop(ctx context.Context) error {
	environmentBackend.stopMutex.Lock()
	defer environmentBackend.stopMutex.Unlock()

	if !environmentBackend.containerCreated || environmentBackend.containerStopped {
		return nil
	}
	environmentBackend.containerStopped = true
	fmt.Fprintln(environmentBackend.config.Output, "Shutting environment down...")

	_, stopErr := environmentBackend.runDocker(
		ctx,
		"stop",
		"--time=3",
		environmentBackend.containerName,
	)
	_, removeErr := environmentBackend.runDocker(
		ctx,
		"rm",
		"-f",
		environmentBackend.containerName,
	)
	if stopErr != nil {
		return fmt.Errorf("stop environment: %w", stopErr)
	}
	if removeErr != nil {
		return fmt.Errorf("remove environment: %w", removeErr)
	}
	return nil
}

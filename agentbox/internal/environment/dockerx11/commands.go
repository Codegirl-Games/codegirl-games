package dockerx11

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

func (environmentBackend *Environment) runDocker(
	ctx context.Context,
	arguments ...string,
) ([]byte, error) {
	command := exec.CommandContext(ctx, "docker", arguments...)
	output, err := command.CombinedOutput()
	if err != nil {
		return output, fmt.Errorf(
			"docker %s: %w: %s",
			arguments[0],
			err,
			strings.TrimSpace(string(output)),
		)
	}
	return output, nil
}

func (environmentBackend *Environment) streamDockerOutput(
	ctx context.Context,
	arguments ...string,
) error {
	command := exec.CommandContext(ctx, "docker", arguments...)
	command.Stdout = environmentBackend.config.Output
	command.Stderr = environmentBackend.config.Output
	return command.Run()
}

func waitFor(ctx context.Context, timeout time.Duration, ready func() bool) error {
	timeoutTimer := time.NewTimer(timeout)
	defer timeoutTimer.Stop()
	retryTicker := time.NewTicker(100 * time.Millisecond)
	defer retryTicker.Stop()

	for {
		if ready() {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-timeoutTimer.C:
			return errors.New("timed out")
		case <-retryTicker.C:
		}
	}
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

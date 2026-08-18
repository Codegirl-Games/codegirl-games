package runtime

import (
	"context"
	"errors"
	"io"
	"testing"

	"agentbox/internal/agent"
	"agentbox/internal/environment"
	"agentbox/internal/trace"
)

type failingStartEnvironment struct {
	stopCalled bool
}

func (fake *failingStartEnvironment) Start(context.Context) error {
	return errors.New("startup failed")
}

func (fake *failingStartEnvironment) Launch(context.Context, environment.Command) error {
	return nil
}

func (fake *failingStartEnvironment) Screenshot(context.Context) ([]byte, error) {
	return nil, nil
}

func (fake *failingStartEnvironment) SendInput(context.Context, environment.InputAction) error {
	return nil
}

func (fake *failingStartEnvironment) Logs(context.Context) ([]environment.LogEntry, error) {
	return nil, nil
}

func (fake *failingStartEnvironment) Stop(context.Context) error {
	fake.stopCalled = true
	return nil
}

func TestRunStopsEnvironmentWhenStartFails(t *testing.T) {
	traceStore, err := trace.New(t.TempDir(), "task", "application", "test-agent")
	if err != nil {
		t.Fatal(err)
	}
	fakeEnvironment := &failingStartEnvironment{}

	err = Run(context.Background(), Config{
		Task:        "task",
		Controller:  &agent.Deterministic{},
		Environment: fakeEnvironment,
		TraceStore:  traceStore,
		Output:      io.Discard,
	})
	if err == nil {
		t.Fatal("Run() error = nil, want startup error")
	}
	if !fakeEnvironment.stopCalled {
		t.Fatal("Run() did not stop environment after startup failure")
	}
}

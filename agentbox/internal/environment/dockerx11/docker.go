package dockerx11

import (
	"io"
	"sync"

	"agentbox/internal/environment"
)

const runtimeImageName = "agentbox-runtime:local"

// Config contains host-side values needed to create one isolated desktop.
type Config struct {
	ProjectRoot string
	RunID       string
	Output      io.Writer
}

// Environment implements the backend-neutral environment contract with one
// Docker container, one X11 display, and one application process.
type Environment struct {
	config        Config
	containerName string

	stopMutex        sync.Mutex
	containerCreated bool
	containerStopped bool
}

func New(config Config) *Environment {
	return &Environment{
		config:        config,
		containerName: "agentbox-run-" + config.RunID,
	}
}

var _ environment.Environment = (*Environment)(nil)

package agent

import (
	"context"
	"time"

	"agentbox/internal/environment"
)

type Observation struct {
	Screenshot      []byte
	Timestamp       time.Time
	Logs            []environment.LogEntry
	PreviousActions []environment.InputAction
}

type Step struct {
	Number         int
	Timestamp      time.Time
	ScreenshotPath string
	Message        string
	Action         *environment.InputAction
}

type Decision struct {
	Reason string
	Action *environment.InputAction
	Done   bool
}

type Agent interface {
	Name() string
	NextAction(
		ctx context.Context,
		task string,
		history []Step,
		observation Observation,
	) (Decision, error)
}

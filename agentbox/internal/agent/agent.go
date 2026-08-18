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

// Step is the compact history passed back to an agent on its next decision.
type Step struct {
	Number         int
	Timestamp      time.Time
	ScreenshotPath string
	Message        string
	Action         *environment.InputAction
}

// Decision contains either one action or Done. Returning neither is invalid.
type Decision struct {
	Reason string
	Action *environment.InputAction
	Done   bool
}

// Agent chooses one backend-neutral action from the latest observation.
type Agent interface {
	Name() string
	NextAction(
		ctx context.Context,
		task string,
		history []Step,
		observation Observation,
	) (Decision, error)
}

package trace

import (
	"time"

	"agentbox/internal/environment"
)

// SchemaVersion changes only when existing trace readers need new logic.
const SchemaVersion = "1"

// Run is the summary stored in run.json.
type Run struct {
	SchemaVersion string    `json:"schema_version"`
	ID            string    `json:"id"`
	Task          string    `json:"task"`
	Application   string    `json:"application"`
	Agent         string    `json:"agent"`
	Status        string    `json:"status"`
	StartedAt     time.Time `json:"started_at"`
	FinishedAt    time.Time `json:"finished_at,omitempty"`
	StepCount     int       `json:"step_count"`
	Error         string    `json:"error,omitempty"`
}

type ObservationRecord struct {
	Screenshot      string                    `json:"screenshot"`
	Logs            []environment.LogEntry    `json:"logs,omitempty"`
	PreviousActions []environment.InputAction `json:"previous_actions,omitempty"`
}

type AgentRecord struct {
	Message string `json:"message"`
}

// StepRecord is one append-only line in steps.jsonl.
type StepRecord struct {
	Step        int                      `json:"step"`
	Timestamp   time.Time                `json:"timestamp"`
	Observation ObservationRecord        `json:"observation"`
	Agent       AgentRecord              `json:"agent"`
	Action      *environment.InputAction `json:"action,omitempty"`
	Done        bool                     `json:"done,omitempty"`
}

type actionRecord struct {
	Step      int                     `json:"step"`
	Timestamp time.Time               `json:"timestamp"`
	Action    environment.InputAction `json:"action"`
}

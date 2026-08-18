package environment

import (
	"context"
	"time"
)

// Command describes a host executable and how it should start in an
// environment. Environment implementations decide how to stage the file.
type Command struct {
	Path                 string
	Args                 []string
	EnvironmentVariables map[string]string
	WindowTitle          string
}

// InputType identifies one backend-neutral keyboard, mouse, or timing action.
type InputType string

const (
	KeyDown   InputType = "key_down"
	KeyUp     InputType = "key_up"
	MouseMove InputType = "mouse_move"
	MouseDown InputType = "mouse_down"
	MouseUp   InputType = "mouse_up"
	Wait      InputType = "wait"
)

// InputAction contains only fields relevant to Type. DurationMS is used by Wait.
type InputAction struct {
	Type       InputType `json:"type"`
	Key        string    `json:"key,omitempty"`
	X          int       `json:"x,omitempty"`
	Y          int       `json:"y,omitempty"`
	Button     int       `json:"button,omitempty"`
	DurationMS int       `json:"duration_ms,omitempty"`
}

// LogEntry is a cumulative snapshot of one application output stream. Time is
// when Agentbox captured the snapshot, not when the application emitted it.
type LogEntry struct {
	Stream  string    `json:"stream"`
	Message string    `json:"message"`
	Time    time.Time `json:"time"`
}

// Environment is the programmable-computer boundary used by the runtime.
// Implementations may use containers, virtual machines, or remote hosts.
type Environment interface {
	Start(context.Context) error
	Launch(context.Context, Command) error
	Screenshot(context.Context) ([]byte, error)
	SendInput(context.Context, InputAction) error
	Logs(context.Context) ([]LogEntry, error)
	Stop(context.Context) error
}

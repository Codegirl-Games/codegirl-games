package environment

import (
	"context"
	"time"
)

type Command struct {
	Path        string
	Args        []string
	Env         map[string]string
	WindowTitle string
}

type InputType string

const (
	KeyDown   InputType = "key_down"
	KeyUp     InputType = "key_up"
	MouseMove InputType = "mouse_move"
	MouseDown InputType = "mouse_down"
	MouseUp   InputType = "mouse_up"
	Wait      InputType = "wait"
)

type InputAction struct {
	Type       InputType `json:"type"`
	Key        string    `json:"key,omitempty"`
	X          int       `json:"x,omitempty"`
	Y          int       `json:"y,omitempty"`
	Button     int       `json:"button,omitempty"`
	DurationMS int       `json:"duration_ms,omitempty"`
}

type LogEntry struct {
	Stream  string    `json:"stream"`
	Message string    `json:"message"`
	Time    time.Time `json:"time"`
}

type Environment interface {
	Start(context.Context) error
	Launch(context.Context, Command) error
	Screenshot(context.Context) ([]byte, error)
	SendInput(context.Context, InputAction) error
	Logs(context.Context) ([]LogEntry, error)
	Stop(context.Context) error
}

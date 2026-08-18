package dockerx11

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"agentbox/internal/environment"
)

func (environmentBackend *Environment) SendInput(
	ctx context.Context,
	action environment.InputAction,
) error {
	var xdotoolArguments []string
	switch action.Type {
	case environment.KeyDown:
		if action.Key == "" {
			return errors.New("key_down requires key")
		}
		xdotoolArguments = []string{"keydown", toX11KeyName(action.Key)}
	case environment.KeyUp:
		if action.Key == "" {
			return errors.New("key_up requires key")
		}
		xdotoolArguments = []string{"keyup", toX11KeyName(action.Key)}
	case environment.MouseMove:
		xdotoolArguments = []string{
			"mousemove",
			strconv.Itoa(action.X),
			strconv.Itoa(action.Y),
		}
	case environment.MouseDown:
		xdotoolArguments = []string{"mousedown", strconv.Itoa(action.Button)}
	case environment.MouseUp:
		xdotoolArguments = []string{"mouseup", strconv.Itoa(action.Button)}
	case environment.Wait:
		if action.DurationMS < 0 {
			return errors.New("wait duration cannot be negative")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Duration(action.DurationMS) * time.Millisecond):
			return nil
		}
	default:
		return fmt.Errorf("unsupported input action %q", action.Type)
	}

	dockerArguments := []string{
		"exec",
		environmentBackend.containerName,
		"xdotool",
	}
	dockerArguments = append(dockerArguments, xdotoolArguments...)
	if _, err := environmentBackend.runDocker(ctx, dockerArguments...); err != nil {
		return fmt.Errorf("send %s: %w", action.Type, err)
	}
	return nil
}

// toX11KeyName keeps X11 spellings out of the public action API. Agents can use
// logical names such as RIGHT even though xdotool expects Right.
func toX11KeyName(logicalName string) string {
	switch strings.ToUpper(logicalName) {
	case "LEFT":
		return "Left"
	case "RIGHT":
		return "Right"
	case "UP":
		return "Up"
	case "DOWN":
		return "Down"
	case "ENTER", "RETURN":
		return "Return"
	case "ESC", "ESCAPE":
		return "Escape"
	case "SPACE":
		return "space"
	case "TAB":
		return "Tab"
	case "BACKSPACE":
		return "BackSpace"
	case "DELETE":
		return "Delete"
	}
	if len(logicalName) == 1 {
		return strings.ToLower(logicalName)
	}
	return logicalName
}

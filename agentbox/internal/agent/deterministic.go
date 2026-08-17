package agent

import (
	"context"
	"time"

	"agentbox/internal/environment"
)

type Deterministic struct {
	next int
}

func (a *Deterministic) Name() string {
	return "deterministic-right"
}

func (a *Deterministic) NextAction(
	_ context.Context,
	_ string,
	_ []Step,
	_ Observation,
) (Decision, error) {
	var decision Decision
	switch a.next {
	case 0:
		action := environment.InputAction{Type: environment.KeyDown, Key: "RIGHT"}
		decision = Decision{Reason: "Press RIGHT to start moving.", Action: &action}
	case 1:
		action := environment.InputAction{Type: environment.Wait, Duration: time.Second}
		decision = Decision{Reason: "Keep RIGHT held for one second.", Action: &action}
	case 2:
		action := environment.InputAction{Type: environment.KeyUp, Key: "RIGHT"}
		decision = Decision{Reason: "Release RIGHT after the movement.", Action: &action}
	default:
		decision = Decision{Reason: "The movement sequence is complete.", Done: true}
	}
	a.next++
	return decision, nil
}

var _ Agent = (*Deterministic)(nil)

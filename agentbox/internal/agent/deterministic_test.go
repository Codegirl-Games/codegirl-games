package agent

import (
	"context"
	"testing"

	"agentbox/internal/environment"
)

func TestDeterministicSequence(t *testing.T) {
	controller := &Deterministic{}
	want := []struct {
		action environment.InputType
		done   bool
	}{
		{environment.KeyDown, false},
		{environment.Wait, false},
		{environment.KeyUp, false},
		{"", true},
	}
	for index, expected := range want {
		decision, err := controller.NextAction(context.Background(), "", nil, Observation{})
		if err != nil {
			t.Fatalf("step %d: %v", index, err)
		}
		if decision.Done != expected.done {
			t.Fatalf("step %d done = %v, want %v", index, decision.Done, expected.done)
		}
		if expected.action != "" && (decision.Action == nil || decision.Action.Type != expected.action) {
			t.Fatalf("step %d action = %#v, want %s", index, decision.Action, expected.action)
		}
	}
}

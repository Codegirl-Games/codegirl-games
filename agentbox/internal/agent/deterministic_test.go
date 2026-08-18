package agent

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/png"
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
		x := 20
		if index >= 2 {
			x = 140
		}
		decision, err := controller.NextAction(context.Background(), "", nil, Observation{
			Screenshot: screenshotWithSquare(t, x),
		})
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

func TestDeterministicRejectsMissingMovement(t *testing.T) {
	controller := &Deterministic{}
	for step := 0; step < 2; step++ {
		if _, err := controller.NextAction(context.Background(), "", nil, Observation{
			Screenshot: screenshotWithSquare(t, 20),
		}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := controller.NextAction(context.Background(), "", nil, Observation{
		Screenshot: screenshotWithSquare(t, 20),
	}); err == nil {
		t.Fatal("movement verification error = nil")
	}
}

func screenshotWithSquare(t *testing.T, startX int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 240, 100))
	green := color.RGBA{G: 255, B: 102, A: 255}
	for y := 20; y < 60; y++ {
		for x := startX; x < startX+40; x++ {
			img.Set(x, y, green)
		}
	}
	var output bytes.Buffer
	if err := png.Encode(&output, img); err != nil {
		t.Fatal(err)
	}
	return output.Bytes()
}

package agent

import (
	"bytes"
	"context"
	"fmt"
	"image/png"

	"agentbox/internal/environment"
)

type Deterministic struct {
	next       int
	initialX   float64
	hasInitial bool
}

func (a *Deterministic) Name() string {
	return "deterministic-right"
}

func (a *Deterministic) NextAction(
	_ context.Context,
	_ string,
	_ []Step,
	observation Observation,
) (Decision, error) {
	var decision Decision
	switch a.next {
	case 0:
		x, err := greenCentroidX(observation.Screenshot)
		if err != nil {
			return Decision{}, fmt.Errorf("inspect initial screenshot: %w", err)
		}
		a.initialX = x
		a.hasInitial = true
		action := environment.InputAction{Type: environment.KeyDown, Key: "RIGHT"}
		decision = Decision{Reason: "Press RIGHT to start moving.", Action: &action}
	case 1:
		action := environment.InputAction{Type: environment.Wait, DurationMS: 1000}
		decision = Decision{Reason: "Keep RIGHT held for one second.", Action: &action}
	case 2:
		x, err := greenCentroidX(observation.Screenshot)
		if err != nil {
			return Decision{}, fmt.Errorf("inspect moved screenshot: %w", err)
		}
		if !a.hasInitial || x-a.initialX < 100 {
			return Decision{}, fmt.Errorf("visual verification failed: square moved %.1f pixels right, want at least 100", x-a.initialX)
		}
		action := environment.InputAction{Type: environment.KeyUp, Key: "RIGHT"}
		decision = Decision{
			Reason: fmt.Sprintf("The square moved %.1f pixels right; release RIGHT.", x-a.initialX),
			Action: &action,
		}
	default:
		decision = Decision{Reason: "The movement sequence is complete.", Done: true}
	}
	a.next++
	return decision, nil
}

func greenCentroidX(screenshot []byte) (float64, error) {
	image, err := png.Decode(bytes.NewReader(screenshot))
	if err != nil {
		return 0, err
	}
	var sumX, count uint64
	bounds := image.Bounds()
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			red, green, blue, _ := image.At(x, y).RGBA()
			if green > 0xc000 && red < 0x4000 && blue < 0x8000 {
				sumX += uint64(x)
				count++
			}
		}
	}
	if count < 1000 {
		return 0, fmt.Errorf("found only %d green square pixels", count)
	}
	return float64(sumX) / float64(count), nil
}

var _ Agent = (*Deterministic)(nil)

package agent

import (
	"bytes"
	"context"
	"fmt"
	"image/png"

	"agentbox/internal/environment"
)

type Deterministic struct {
	nextStep           int
	initialSquareX     float64
	hasInitialPosition bool
}

func (deterministicAgent *Deterministic) Name() string {
	return "deterministic-right"
}

func (deterministicAgent *Deterministic) NextAction(
	_ context.Context,
	_ string,
	_ []Step,
	observation Observation,
) (Decision, error) {
	var decision Decision
	switch deterministicAgent.nextStep {
	case 0:
		initialSquareX, err := greenCentroidX(observation.Screenshot)
		if err != nil {
			return Decision{}, fmt.Errorf("inspect initial screenshot: %w", err)
		}
		deterministicAgent.initialSquareX = initialSquareX
		deterministicAgent.hasInitialPosition = true
		action := environment.InputAction{Type: environment.KeyDown, Key: "RIGHT"}
		decision = Decision{Reason: "Press RIGHT to start moving.", Action: &action}
	case 1:
		action := environment.InputAction{Type: environment.Wait, DurationMS: 1000}
		decision = Decision{Reason: "Keep RIGHT held for one second.", Action: &action}
	case 2:
		currentSquareX, err := greenCentroidX(observation.Screenshot)
		if err != nil {
			return Decision{}, fmt.Errorf("inspect moved screenshot: %w", err)
		}
		distanceMoved := currentSquareX - deterministicAgent.initialSquareX
		if !deterministicAgent.hasInitialPosition || distanceMoved < 100 {
			return Decision{}, fmt.Errorf(
				"visual verification failed: square moved %.1f pixels right, want at least 100",
				distanceMoved,
			)
		}
		action := environment.InputAction{Type: environment.KeyUp, Key: "RIGHT"}
		decision = Decision{
			Reason: fmt.Sprintf(
				"The square moved %.1f pixels right; release RIGHT.",
				distanceMoved,
			),
			Action: &action,
		}
	default:
		decision = Decision{Reason: "The movement sequence is complete.", Done: true}
	}
	deterministicAgent.nextStep++
	return decision, nil
}

func greenCentroidX(screenshot []byte) (float64, error) {
	renderedImage, err := png.Decode(bytes.NewReader(screenshot))
	if err != nil {
		return 0, err
	}
	var xCoordinateSum, greenPixelCount uint64
	bounds := renderedImage.Bounds()
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			red, green, blue, _ := renderedImage.At(x, y).RGBA()
			if green > 0xc000 && red < 0x4000 && blue < 0x8000 {
				xCoordinateSum += uint64(x)
				greenPixelCount++
			}
		}
	}
	if greenPixelCount < 1000 {
		return 0, fmt.Errorf("found only %d green square pixels", greenPixelCount)
	}
	return float64(xCoordinateSum) / float64(greenPixelCount), nil
}

var _ Agent = (*Deterministic)(nil)

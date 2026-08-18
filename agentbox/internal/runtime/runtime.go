package runtime

import (
	"context"
	"errors"
	"fmt"
	"io"
	"time"

	"agentbox/internal/agent"
	"agentbox/internal/environment"
	"agentbox/internal/trace"
)

// Config wires replaceable environment, agent, and trace implementations into
// one run. The runtime itself has no Docker, X11, or model-provider knowledge.
type Config struct {
	Task        string
	Command     environment.Command
	Controller  agent.Agent
	Environment environment.Environment
	TraceStore  *trace.Store
	MaxSteps    int
	Output      io.Writer
}

func Run(ctx context.Context, config Config) (runErr error) {
	if config.MaxSteps <= 0 {
		config.MaxSteps = 20
	}
	if config.Output == nil {
		config.Output = io.Discard
	}
	if config.Controller == nil || config.Environment == nil || config.TraceStore == nil {
		return errors.New("runtime requires agent, environment, and trace")
	}

	defer func() {
		runErr = finalizeRun(config, runErr)
	}()

	if err := config.Environment.Start(ctx); err != nil {
		return err
	}
	if err := config.Environment.Launch(ctx, config.Command); err != nil {
		return err
	}
	fmt.Fprintln(config.Output, "Agent loop started.")

	var stepHistory []agent.Step
	var actionHistory []environment.InputAction
	runStartedAt := time.Now()
	for stepNumber := 1; stepNumber <= config.MaxSteps; stepNumber++ {
		screenshot, err := config.Environment.Screenshot(ctx)
		if err != nil {
			return err
		}
		screenshotPath, err := config.TraceStore.SaveScreenshot(stepNumber, screenshot)
		if err != nil {
			return err
		}
		applicationLogs, err := config.Environment.Logs(ctx)
		if err != nil {
			return err
		}
		observedAt := time.Now().UTC()
		previousActions := append([]environment.InputAction(nil), actionHistory...)
		observation := agent.Observation{
			Screenshot:      screenshot,
			Timestamp:       observedAt,
			Logs:            applicationLogs,
			PreviousActions: previousActions,
		}
		fmt.Fprintf(config.Output, "[%s] screenshot captured\n", elapsed(runStartedAt))

		decision, err := config.Controller.NextAction(
			ctx,
			config.Task,
			stepHistory,
			observation,
		)
		if err != nil {
			return fmt.Errorf("agent next action: %w", err)
		}
		fmt.Fprintf(
			config.Output,
			"[%s] agent: %s\n",
			elapsed(runStartedAt),
			decision.Reason,
		)
		if err := config.TraceStore.Record(trace.StepRecord{
			Step:      stepNumber,
			Timestamp: observedAt,
			Observation: trace.ObservationRecord{
				Screenshot:      screenshotPath,
				Logs:            applicationLogs,
				PreviousActions: previousActions,
			},
			Agent:  trace.AgentRecord{Message: decision.Reason},
			Action: decision.Action,
			Done:   decision.Done,
		}); err != nil {
			return err
		}
		stepHistory = append(stepHistory, agent.Step{
			Number:         stepNumber,
			Timestamp:      observedAt,
			ScreenshotPath: screenshotPath,
			Message:        decision.Reason,
			Action:         decision.Action,
		})

		if decision.Done {
			fmt.Fprintln(config.Output, "Task complete.")
			return nil
		}
		if decision.Action == nil {
			return errors.New("agent returned neither action nor completion")
		}
		fmt.Fprintf(
			config.Output,
			"[%s] action: %s%s\n",
			elapsed(runStartedAt),
			decision.Action.Type,
			actionDetail(*decision.Action),
		)
		if err := config.Environment.SendInput(ctx, *decision.Action); err != nil {
			return err
		}
		actionHistory = append(actionHistory, *decision.Action)
	}
	return fmt.Errorf("agent exceeded maximum of %d steps", config.MaxSteps)
}

// finalizeRun uses a fresh timeout because the caller's context may already be
// canceled. Preserving logs and removing the environment must still be tried.
func finalizeRun(
	config Config,
	runErr error,
) error {
	cleanupCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if logs, err := config.Environment.Logs(cleanupCtx); err == nil {
		if logErr := config.TraceStore.WriteLogs(logs); runErr == nil && logErr != nil {
			runErr = logErr
		}
	}
	// Stop is idempotent, so always call it. Start may have created a container
	// before returning an error while waiting for its graphical services.
	if stopErr := config.Environment.Stop(cleanupCtx); runErr == nil && stopErr != nil {
		runErr = stopErr
	}
	if finishErr := config.TraceStore.Finish(runErr); runErr == nil && finishErr != nil {
		runErr = finishErr
	}
	return runErr
}

func elapsed(start time.Time) string {
	duration := time.Since(start).Round(time.Second)
	return fmt.Sprintf(
		"%02d:%02d",
		int(duration.Minutes()),
		int(duration.Seconds())%60,
	)
}

func actionDetail(action environment.InputAction) string {
	switch action.Type {
	case environment.KeyDown, environment.KeyUp:
		return " " + action.Key
	case environment.MouseMove:
		return fmt.Sprintf(" %d,%d", action.X, action.Y)
	case environment.MouseDown, environment.MouseUp:
		return fmt.Sprintf(" %d", action.Button)
	case environment.Wait:
		return fmt.Sprintf(" %dms", action.DurationMS)
	default:
		return ""
	}
}

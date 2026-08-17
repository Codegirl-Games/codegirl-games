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

type Config struct {
	Task     string
	Command  environment.Command
	Agent    agent.Agent
	Env      environment.Environment
	Trace    *trace.Store
	MaxSteps int
	Output   io.Writer
}

func Run(ctx context.Context, config Config) (runErr error) {
	if config.MaxSteps <= 0 {
		config.MaxSteps = 20
	}
	if config.Output == nil {
		config.Output = io.Discard
	}
	if config.Agent == nil || config.Env == nil || config.Trace == nil {
		return errors.New("runtime requires agent, environment, and trace")
	}

	started := false
	defer func() {
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if started {
			if logs, err := config.Env.Logs(cleanupCtx); err == nil {
				if logErr := config.Trace.WriteLogs(logs); runErr == nil && logErr != nil {
					runErr = logErr
				}
			}
			if stopErr := config.Env.Stop(cleanupCtx); runErr == nil && stopErr != nil {
				runErr = stopErr
			}
		}
		if finishErr := config.Trace.Finish(runErr); runErr == nil && finishErr != nil {
			runErr = finishErr
		}
	}()

	if err := config.Env.Start(ctx); err != nil {
		return err
	}
	started = true
	if err := config.Env.Launch(ctx, config.Command); err != nil {
		return err
	}
	fmt.Fprintln(config.Output, "Agent attached.")

	var history []agent.Step
	var actions []environment.InputAction
	startedAt := time.Now()
	for number := 1; number <= config.MaxSteps; number++ {
		screenshot, err := config.Env.Screenshot(ctx)
		if err != nil {
			return err
		}
		screenshotPath, err := config.Trace.SaveScreenshot(number, screenshot)
		if err != nil {
			return err
		}
		logs, err := config.Env.Logs(ctx)
		if err != nil {
			return err
		}
		now := time.Now().UTC()
		fmt.Fprintf(config.Output, "[%s] screenshot captured\n", elapsed(startedAt))
		decision, err := config.Agent.NextAction(ctx, config.Task, history, agent.Observation{
			Screenshot:      screenshot,
			Timestamp:       now,
			Logs:            logs,
			PreviousActions: append([]environment.InputAction(nil), actions...),
		})
		if err != nil {
			return fmt.Errorf("agent next action: %w", err)
		}
		fmt.Fprintf(config.Output, "[%s] agent: %s\n", elapsed(startedAt), decision.Reason)
		record := trace.StepRecord{
			Step:      number,
			Timestamp: now,
			Observation: trace.ObservationRecord{
				Screenshot:      screenshotPath,
				Logs:            logs,
				PreviousActions: append([]environment.InputAction(nil), actions...),
			},
			Agent:  trace.AgentRecord{Message: decision.Reason},
			Action: decision.Action,
			Done:   decision.Done,
		}
		if err := config.Trace.Record(record); err != nil {
			return err
		}
		history = append(history, agent.Step{
			Number:         number,
			Timestamp:      now,
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
		fmt.Fprintf(config.Output, "[%s] action: %s%s\n",
			elapsed(startedAt), decision.Action.Type, actionDetail(*decision.Action))
		if err := config.Env.SendInput(ctx, *decision.Action); err != nil {
			return err
		}
		actions = append(actions, *decision.Action)
	}
	return fmt.Errorf("agent exceeded maximum of %d steps", config.MaxSteps)
}

func elapsed(start time.Time) string {
	duration := time.Since(start).Round(time.Second)
	return fmt.Sprintf("%02d:%02d", int(duration.Minutes()), int(duration.Seconds())%60)
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
		return " " + action.Duration.String()
	default:
		return ""
	}
}

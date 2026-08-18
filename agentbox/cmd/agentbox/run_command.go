package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"

	"agentbox/internal/agent"
	"agentbox/internal/appspec"
	"agentbox/internal/environment/dockerx11"
	agentRuntime "agentbox/internal/runtime"
	"agentbox/internal/trace"
)

type runOptions struct {
	applicationPath string
	task            string
	agentName       string
	modelName       string
	maxSteps        int
}

func run(ctx context.Context, args []string) error {
	options, err := parseRunOptions(args)
	if err != nil {
		return err
	}
	projectRoot, err := findProjectRoot()
	if err != nil {
		return err
	}
	applicationCommand, err := appspec.Resolve(options.applicationPath)
	if err != nil {
		return err
	}
	controller, err := newAgent(options)
	if err != nil {
		return err
	}
	traceStore, err := trace.New(
		projectRoot,
		options.task,
		options.applicationPath,
		controller.Name(),
	)
	if err != nil {
		return err
	}
	desktopEnvironment := dockerx11.New(dockerx11.Config{
		ProjectRoot: projectRoot,
		RunID:       traceStore.ID(),
		Output:      os.Stdout,
	})
	err = agentRuntime.Run(ctx, agentRuntime.Config{
		Task:        options.task,
		Command:     applicationCommand,
		Controller:  controller,
		Environment: desktopEnvironment,
		TraceStore:  traceStore,
		MaxSteps:    options.maxSteps,
		Output:      os.Stdout,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Run artifacts: %s\n", traceStore.Directory())
		return err
	}
	fmt.Printf("Run artifacts written to:\n%s\n", traceStore.Directory())
	return nil
}

// parseRunOptions accepts flags before or after the application path so the CLI
// matches the natural "agentbox run ./app --task ..." form shown in the docs.
func parseRunOptions(args []string) (runOptions, error) {
	options := runOptions{
		agentName: "deterministic",
		modelName: "gpt-5",
		maxSteps:  20,
	}
	for index := 0; index < len(args); index++ {
		argument := args[index]
		if !strings.HasPrefix(argument, "--") {
			if options.applicationPath != "" {
				return options, errors.New("run accepts exactly one application path")
			}
			options.applicationPath = argument
			continue
		}

		flagName, flagValue, _ := strings.Cut(strings.TrimPrefix(argument, "--"), "=")
		if flagValue == "" {
			index++
			if index >= len(args) {
				return options, fmt.Errorf("--%s requires a value", flagName)
			}
			flagValue = args[index]
		}
		switch flagName {
		case "task":
			options.task = flagValue
		case "agent":
			options.agentName = flagValue
		case "model":
			options.modelName = flagValue
		case "max-steps":
			maxSteps, err := strconv.Atoi(flagValue)
			if err != nil || maxSteps < 1 {
				return options, errors.New("--max-steps must be a positive integer")
			}
			options.maxSteps = maxSteps
		default:
			return options, fmt.Errorf("unknown flag --%s", flagName)
		}
	}
	if options.applicationPath == "" {
		return options, errors.New("run requires an application path")
	}
	if options.task == "" {
		return options, errors.New("run requires --task")
	}
	return options, nil
}

func newAgent(options runOptions) (agent.Agent, error) {
	switch options.agentName {
	case "deterministic":
		return &agent.Deterministic{}, nil
	case "openai":
		return agent.NewOpenAI(agent.OpenAIConfig{
			APIKey: os.Getenv("OPENAI_API_KEY"),
			Model:  options.modelName,
		})
	default:
		return nil, fmt.Errorf(
			"unknown agent %q (want deterministic or openai)",
			options.agentName,
		)
	}
}

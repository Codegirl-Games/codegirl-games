package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"agentbox/internal/agent"
	"agentbox/internal/appspec"
	"agentbox/internal/environment/dockerx11"
	"agentbox/internal/phase1"
	agentRuntime "agentbox/internal/runtime"
	"agentbox/internal/trace"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	var err error
	switch os.Args[1] {
	case "phase1":
		err = phase1.Run(ctx)
	case "run":
		err = run(ctx, os.Args[2:])
	case "runs":
		err = listRuns()
	case "inspect":
		err = inspect(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "agentbox: %v\n", err)
		os.Exit(1)
	}
}

type runOptions struct {
	path     string
	task     string
	agent    string
	model    string
	maxSteps int
}

func run(ctx context.Context, args []string) error {
	options, err := parseRunOptions(args)
	if err != nil {
		return err
	}
	root, err := findRoot()
	if err != nil {
		return err
	}
	command, err := appspec.Resolve(options.path)
	if err != nil {
		return err
	}
	controller, err := selectAgent(options)
	if err != nil {
		return err
	}
	store, err := trace.New(root, options.task, options.path, controller.Name())
	if err != nil {
		return err
	}
	env := dockerx11.New(dockerx11.Config{
		ProjectRoot: root,
		RunID:       store.ID(),
		Output:      os.Stdout,
	})
	err = agentRuntime.Run(ctx, agentRuntime.Config{
		Task:     options.task,
		Command:  command,
		Agent:    controller,
		Env:      env,
		Trace:    store,
		MaxSteps: options.maxSteps,
		Output:   os.Stdout,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Run artifacts: %s\n", store.Directory())
		return err
	}
	fmt.Printf("Replay written to:\n%s\n", store.Directory())
	return nil
}

func parseRunOptions(args []string) (runOptions, error) {
	options := runOptions{agent: "deterministic", model: "gpt-5", maxSteps: 20}
	for index := 0; index < len(args); index++ {
		arg := args[index]
		var name, value string
		if strings.HasPrefix(arg, "--") {
			name, value, _ = strings.Cut(strings.TrimPrefix(arg, "--"), "=")
			if value == "" {
				index++
				if index >= len(args) {
					return options, fmt.Errorf("--%s requires a value", name)
				}
				value = args[index]
			}
			switch name {
			case "task":
				options.task = value
			case "agent":
				options.agent = value
			case "model":
				options.model = value
			case "max-steps":
				number, err := strconv.Atoi(value)
				if err != nil || number < 1 {
					return options, errors.New("--max-steps must be a positive integer")
				}
				options.maxSteps = number
			default:
				return options, fmt.Errorf("unknown flag --%s", name)
			}
			continue
		}
		if options.path != "" {
			return options, errors.New("run accepts exactly one application path")
		}
		options.path = arg
	}
	if options.path == "" {
		return options, errors.New("run requires an application path")
	}
	if options.task == "" {
		return options, errors.New("run requires --task")
	}
	return options, nil
}

func selectAgent(options runOptions) (agent.Agent, error) {
	switch options.agent {
	case "deterministic":
		return &agent.Deterministic{}, nil
	case "openai":
		return agent.NewOpenAI(agent.OpenAIConfig{
			APIKey: os.Getenv("OPENAI_API_KEY"),
			Model:  options.model,
		})
	default:
		return nil, fmt.Errorf("unknown agent %q (want deterministic or openai)", options.agent)
	}
}

func listRuns() error {
	root, err := findRoot()
	if err != nil {
		return err
	}
	runs, err := trace.List(root)
	if err != nil {
		return err
	}
	if len(runs) == 0 {
		fmt.Println("No recorded runs.")
		return nil
	}
	for _, run := range runs {
		fmt.Printf("%s  %-8s  %-20s  %s\n",
			run.ID, run.Status, run.Agent, run.Task)
	}
	return nil
}

func inspect(args []string) error {
	if len(args) != 1 {
		return errors.New("inspect requires one run ID")
	}
	root, err := findRoot()
	if err != nil {
		return err
	}
	run, err := trace.Read(root, args[0])
	if err != nil {
		return err
	}
	steps, err := trace.ReadSteps(root, args[0])
	if err != nil {
		return err
	}
	output := struct {
		Run       trace.Run          `json:"run"`
		Steps     []trace.StepRecord `json:"steps"`
		Directory string             `json:"directory"`
	}{
		Run:       run,
		Steps:     steps,
		Directory: filepath.Join(root, ".agentbox", "runs", run.ID),
	}
	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(data))
	return nil
}

func findRoot() (string, error) {
	current, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		data, readErr := os.ReadFile(filepath.Join(current, "go.mod"))
		if readErr == nil && bytes.Contains(data, []byte("module agentbox")) {
			return current, nil
		}
		parent := filepath.Dir(current)
		if parent == current {
			return "", errors.New("run agentbox from inside its module directory")
		}
		current = parent
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `usage:
  agentbox run <path> --task "<task>" [--agent deterministic|openai] [--model <model>]
  agentbox runs
  agentbox inspect <run-id>
  agentbox phase1`)
}

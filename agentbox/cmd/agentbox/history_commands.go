package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"

	"agentbox/internal/trace"
)

func listRuns() error {
	projectRoot, err := findProjectRoot()
	if err != nil {
		return err
	}
	runs, err := trace.List(projectRoot)
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
	projectRoot, err := findProjectRoot()
	if err != nil {
		return err
	}
	runID := args[0]
	run, err := trace.Read(projectRoot, runID)
	if err != nil {
		return err
	}
	steps, err := trace.ReadSteps(projectRoot, runID)
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
		Directory: filepath.Join(projectRoot, ".agentbox", "runs", run.ID),
	}
	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(data))
	return nil
}

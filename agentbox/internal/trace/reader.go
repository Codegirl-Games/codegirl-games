package trace

import (
	"bufio"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
)

func List(projectRoot string) ([]Run, error) {
	runsDirectory := filepath.Join(projectRoot, ".agentbox", "runs")
	directoryEntries, err := os.ReadDir(runsDirectory)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	var runs []Run
	for _, entry := range directoryEntries {
		if !entry.IsDir() {
			continue
		}
		run, err := Read(projectRoot, entry.Name())
		// Old or malformed trace directories are intentionally hidden rather
		// than making the entire run listing fail.
		if err == nil && run.SchemaVersion == SchemaVersion {
			runs = append(runs, run)
		}
	}
	sort.Slice(runs, func(left, right int) bool {
		return runs[left].StartedAt.After(runs[right].StartedAt)
	})
	return runs, nil
}

func Read(projectRoot, runID string) (Run, error) {
	if err := validateRunID(runID); err != nil {
		return Run{}, err
	}
	runPath := filepath.Join(
		projectRoot,
		".agentbox",
		"runs",
		runID,
		"run.json",
	)
	data, err := os.ReadFile(runPath)
	if err != nil {
		return Run{}, err
	}
	var run Run
	if err := json.Unmarshal(data, &run); err != nil {
		return Run{}, err
	}
	return run, nil
}

func ReadSteps(projectRoot, runID string) ([]StepRecord, error) {
	if err := validateRunID(runID); err != nil {
		return nil, err
	}
	stepsPath := filepath.Join(
		projectRoot,
		".agentbox",
		"runs",
		runID,
		"steps.jsonl",
	)
	stepsFile, err := os.Open(stepsPath)
	if err != nil {
		return nil, err
	}
	defer stepsFile.Close()

	var steps []StepRecord
	scanner := bufio.NewScanner(stepsFile)
	for scanner.Scan() {
		var step StepRecord
		if err := json.Unmarshal(scanner.Bytes(), &step); err != nil {
			return nil, err
		}
		steps = append(steps, step)
	}
	return steps, scanner.Err()
}

func validateRunID(runID string) error {
	// Run IDs become path components, so reject separators and traversal.
	if filepath.Base(runID) != runID {
		return errors.New("invalid run ID")
	}
	return nil
}

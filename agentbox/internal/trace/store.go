package trace

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"agentbox/internal/environment"
)

// Store writes one run's metadata and append-only event streams.
type Store struct {
	runDirectory string
	run          Run
	stepsFile    *os.File
	actionsFile  *os.File
}

func New(projectRoot, task, application, agentName string) (*Store, error) {
	runID, err := newRunID()
	if err != nil {
		return nil, err
	}
	runDirectory := filepath.Join(projectRoot, ".agentbox", "runs", runID)
	screenshotDirectory := filepath.Join(runDirectory, "screenshots")
	if err := os.MkdirAll(screenshotDirectory, 0o755); err != nil {
		return nil, fmt.Errorf("create run directory: %w", err)
	}
	stepsFile, err := os.Create(filepath.Join(runDirectory, "steps.jsonl"))
	if err != nil {
		return nil, fmt.Errorf("create step trace: %w", err)
	}
	actionsFile, err := os.Create(filepath.Join(runDirectory, "actions.jsonl"))
	if err != nil {
		_ = stepsFile.Close()
		return nil, fmt.Errorf("create action trace: %w", err)
	}

	store := &Store{
		runDirectory: runDirectory,
		stepsFile:    stepsFile,
		actionsFile:  actionsFile,
		run: Run{
			SchemaVersion: SchemaVersion,
			ID:            runID,
			Task:          task,
			Application:   application,
			Agent:         agentName,
			Status:        "running",
			StartedAt:     time.Now().UTC(),
		},
	}
	if err := store.writeRunSummary(); err != nil {
		_ = stepsFile.Close()
		_ = actionsFile.Close()
		return nil, err
	}
	return store, nil
}

func (store *Store) ID() string {
	return store.run.ID
}

func (store *Store) Directory() string {
	return store.runDirectory
}

func (store *Store) SaveScreenshot(stepNumber int, screenshot []byte) (string, error) {
	relativePath := filepath.Join(
		"screenshots",
		fmt.Sprintf("%04d.png", stepNumber),
	)
	absolutePath := filepath.Join(store.runDirectory, relativePath)
	if err := os.WriteFile(absolutePath, screenshot, 0o644); err != nil {
		return "", fmt.Errorf("write screenshot: %w", err)
	}
	// Trace paths always use slash separators so traces are portable.
	return filepath.ToSlash(relativePath), nil
}

func (store *Store) Record(step StepRecord) error {
	if err := appendJSONLine(store.stepsFile, step); err != nil {
		return fmt.Errorf("record step: %w", err)
	}
	if step.Action != nil {
		action := actionRecord{
			Step:      step.Step,
			Timestamp: step.Timestamp,
			Action:    *step.Action,
		}
		if err := appendJSONLine(store.actionsFile, action); err != nil {
			return fmt.Errorf("record action: %w", err)
		}
	}
	store.run.StepCount = step.Step
	return store.writeRunSummary()
}

func (store *Store) WriteLogs(logEntries []environment.LogEntry) error {
	var standardOutput, standardError string
	for _, entry := range logEntries {
		switch entry.Stream {
		case "stdout":
			standardOutput = entry.Message
		case "stderr":
			standardError = entry.Message
		}
	}
	if err := os.WriteFile(
		filepath.Join(store.runDirectory, "stdout.log"),
		[]byte(standardOutput),
		0o644,
	); err != nil {
		return err
	}
	return os.WriteFile(
		filepath.Join(store.runDirectory, "stderr.log"),
		[]byte(standardError),
		0o644,
	)
}

func (store *Store) Finish(runErr error) error {
	store.closeEventFiles()
	store.run.FinishedAt = time.Now().UTC()
	if runErr != nil {
		store.run.Status = "failed"
		store.run.Error = runErr.Error()
	} else {
		store.run.Status = "complete"
	}
	return store.writeRunSummary()
}

func (store *Store) closeEventFiles() {
	if store.stepsFile != nil {
		_ = store.stepsFile.Close()
		store.stepsFile = nil
	}
	if store.actionsFile != nil {
		_ = store.actionsFile.Close()
		store.actionsFile = nil
	}
}

// Sync each JSONL record so an interrupted run retains its latest complete
// decision. Performance is secondary to debuggability in this local spike.
func appendJSONLine(file *os.File, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	if _, err := file.Write(append(data, '\n')); err != nil {
		return err
	}
	return file.Sync()
}

func (store *Store) writeRunSummary() error {
	data, err := json.MarshalIndent(store.run, "", "  ")
	if err != nil {
		return err
	}
	runPath := filepath.Join(store.runDirectory, "run.json")
	return os.WriteFile(runPath, append(data, '\n'), 0o644)
}

func newRunID() (string, error) {
	randomSuffix := make([]byte, 3)
	if _, err := rand.Read(randomSuffix); err != nil {
		return "", err
	}
	timestamp := time.Now().UTC().Format("20060102T150405")
	return timestamp + "-" + hex.EncodeToString(randomSuffix), nil
}

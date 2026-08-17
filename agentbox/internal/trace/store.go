package trace

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"

	"agentbox/internal/environment"
)

const SchemaVersion = "1"

type Run struct {
	SchemaVersion string    `json:"schema_version"`
	ID            string    `json:"id"`
	Task          string    `json:"task"`
	Application   string    `json:"application"`
	Agent         string    `json:"agent"`
	Status        string    `json:"status"`
	StartedAt     time.Time `json:"started_at"`
	FinishedAt    time.Time `json:"finished_at,omitempty"`
	StepCount     int       `json:"step_count"`
	Error         string    `json:"error,omitempty"`
}

type ObservationRecord struct {
	Screenshot      string                    `json:"screenshot"`
	Logs            []environment.LogEntry    `json:"logs,omitempty"`
	PreviousActions []environment.InputAction `json:"previous_actions,omitempty"`
}

type AgentRecord struct {
	Message string `json:"message"`
}

type StepRecord struct {
	Step        int                      `json:"step"`
	Timestamp   time.Time                `json:"timestamp"`
	Observation ObservationRecord        `json:"observation"`
	Agent       AgentRecord              `json:"agent"`
	Action      *environment.InputAction `json:"action,omitempty"`
	Done        bool                     `json:"done,omitempty"`
}

type Store struct {
	root    string
	runDir  string
	run     Run
	steps   *os.File
	actions *os.File
}

func New(root, task, application, agentName string) (*Store, error) {
	id, err := newID()
	if err != nil {
		return nil, err
	}
	runDir := filepath.Join(root, ".agentbox", "runs", id)
	if err := os.MkdirAll(filepath.Join(runDir, "screenshots"), 0o755); err != nil {
		return nil, fmt.Errorf("create run directory: %w", err)
	}
	steps, err := os.Create(filepath.Join(runDir, "steps.jsonl"))
	if err != nil {
		return nil, fmt.Errorf("create step trace: %w", err)
	}
	actions, err := os.Create(filepath.Join(runDir, "actions.jsonl"))
	if err != nil {
		_ = steps.Close()
		return nil, fmt.Errorf("create action trace: %w", err)
	}
	store := &Store{
		root: root, runDir: runDir, steps: steps, actions: actions,
		run: Run{
			SchemaVersion: SchemaVersion,
			ID:            id,
			Task:          task,
			Application:   application,
			Agent:         agentName,
			Status:        "running",
			StartedAt:     time.Now().UTC(),
		},
	}
	if err := store.writeRun(); err != nil {
		_ = steps.Close()
		_ = actions.Close()
		return nil, err
	}
	return store, nil
}

func (s *Store) ID() string {
	return s.run.ID
}

func (s *Store) Directory() string {
	return s.runDir
}

func (s *Store) SaveScreenshot(step int, data []byte) (string, error) {
	relative := filepath.Join("screenshots", fmt.Sprintf("%04d.png", step))
	if err := os.WriteFile(filepath.Join(s.runDir, relative), data, 0o644); err != nil {
		return "", fmt.Errorf("write screenshot: %w", err)
	}
	return filepath.ToSlash(relative), nil
}

func (s *Store) Record(record StepRecord) error {
	if err := appendJSON(s.steps, record); err != nil {
		return fmt.Errorf("record step: %w", err)
	}
	if record.Action != nil {
		action := struct {
			Step      int                     `json:"step"`
			Timestamp time.Time               `json:"timestamp"`
			Action    environment.InputAction `json:"action"`
		}{record.Step, record.Timestamp, *record.Action}
		if err := appendJSON(s.actions, action); err != nil {
			return fmt.Errorf("record action: %w", err)
		}
	}
	s.run.StepCount = record.Step
	return s.writeRun()
}

func (s *Store) WriteLogs(logs []environment.LogEntry) error {
	var stdout, stderr string
	for _, entry := range logs {
		if entry.Stream == "stderr" {
			stderr = entry.Message
		} else if entry.Stream == "stdout" {
			stdout = entry.Message
		}
	}
	if err := os.WriteFile(filepath.Join(s.runDir, "stdout.log"), []byte(stdout), 0o644); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(s.runDir, "stderr.log"), []byte(stderr), 0o644)
}

func (s *Store) Finish(runErr error) error {
	if s.steps != nil {
		_ = s.steps.Close()
		s.steps = nil
	}
	if s.actions != nil {
		_ = s.actions.Close()
		s.actions = nil
	}
	s.run.FinishedAt = time.Now().UTC()
	if runErr != nil {
		s.run.Status = "failed"
		s.run.Error = runErr.Error()
	} else {
		s.run.Status = "complete"
	}
	return s.writeRun()
}

func List(root string) ([]Run, error) {
	directories, err := os.ReadDir(filepath.Join(root, ".agentbox", "runs"))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var runs []Run
	for _, directory := range directories {
		if !directory.IsDir() {
			continue
		}
		run, err := Read(root, directory.Name())
		if err == nil && run.SchemaVersion == SchemaVersion {
			runs = append(runs, run)
		}
	}
	sort.Slice(runs, func(i, j int) bool {
		return runs[i].StartedAt.After(runs[j].StartedAt)
	})
	return runs, nil
}

func Read(root, id string) (Run, error) {
	if filepath.Base(id) != id {
		return Run{}, errors.New("invalid run ID")
	}
	data, err := os.ReadFile(filepath.Join(root, ".agentbox", "runs", id, "run.json"))
	if err != nil {
		return Run{}, err
	}
	var run Run
	if err := json.Unmarshal(data, &run); err != nil {
		return Run{}, err
	}
	return run, nil
}

func ReadSteps(root, id string) ([]StepRecord, error) {
	if filepath.Base(id) != id {
		return nil, errors.New("invalid run ID")
	}
	file, err := os.Open(filepath.Join(root, ".agentbox", "runs", id, "steps.jsonl"))
	if err != nil {
		return nil, err
	}
	defer file.Close()
	var steps []StepRecord
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		var step StepRecord
		if err := json.Unmarshal(scanner.Bytes(), &step); err != nil {
			return nil, err
		}
		steps = append(steps, step)
	}
	return steps, scanner.Err()
}

func appendJSON(file *os.File, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	if _, err := file.Write(append(data, '\n')); err != nil {
		return err
	}
	return file.Sync()
}

func (s *Store) writeRun() error {
	data, err := json.MarshalIndent(s.run, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(s.runDir, "run.json"), append(data, '\n'), 0o644)
}

func newID() (string, error) {
	random := make([]byte, 3)
	if _, err := rand.Read(random); err != nil {
		return "", err
	}
	return time.Now().UTC().Format("20060102T150405") + "-" + hex.EncodeToString(random), nil
}

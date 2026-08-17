package phase1

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const imageName = "agentbox-phase1:local"

type point struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type runRecord struct {
	ID              string    `json:"id"`
	Phase           string    `json:"phase"`
	Status          string    `json:"status"`
	StartedAt       time.Time `json:"started_at"`
	FinishedAt      time.Time `json:"finished_at"`
	ContainerEngine string    `json:"container_engine"`
	Before          *point    `json:"square_before,omitempty"`
	After           *point    `json:"square_after,omitempty"`
	MovementPixels  float64   `json:"movement_pixels,omitempty"`
	Error           string    `json:"error,omitempty"`
}

type actionRecord struct {
	Timestamp time.Time `json:"timestamp"`
	Type      string    `json:"type"`
	Key       string    `json:"key,omitempty"`
	X         int       `json:"x,omitempty"`
	Y         int       `json:"y,omitempty"`
	Button    int       `json:"button,omitempty"`
	Duration  string    `json:"duration,omitempty"`
}

type runner struct {
	root          string
	runDir        string
	containerName string
	containerMade bool
	actions       *os.File
	record        runRecord
}

func Run(ctx context.Context) (runErr error) {
	root, err := findRoot()
	if err != nil {
		return err
	}
	id, err := runID()
	if err != nil {
		return fmt.Errorf("create run ID: %w", err)
	}

	runDir := filepath.Join(root, ".agentbox", "runs", id)
	if err := os.MkdirAll(filepath.Join(runDir, "screenshots"), 0o755); err != nil {
		return fmt.Errorf("create run directory: %w", err)
	}
	actions, err := os.Create(filepath.Join(runDir, "actions.jsonl"))
	if err != nil {
		return fmt.Errorf("create action trace: %w", err)
	}

	r := &runner{
		root:          root,
		runDir:        runDir,
		containerName: "agentbox-phase1-" + id,
		actions:       actions,
		record: runRecord{
			ID:        id,
			Phase:     "environment-prototype",
			Status:    "running",
			StartedAt: time.Now().UTC(),
		},
	}
	defer func() {
		cleanupErr := r.cleanup()
		r.record.FinishedAt = time.Now().UTC()
		if runErr == nil && cleanupErr != nil {
			runErr = cleanupErr
		}
		if runErr != nil {
			r.record.Status = "failed"
			r.record.Error = runErr.Error()
		} else {
			r.record.Status = "passed"
		}
		if err := r.writeRecord(); err != nil && runErr == nil {
			runErr = err
		}
	}()

	fmt.Println("Checking container engine...")
	version, err := r.docker(ctx, "version", "--format", "{{.Server.Version}}")
	if err != nil {
		return fmt.Errorf("Docker is required and the daemon must be accessible: %w", err)
	}
	r.record.ContainerEngine = "Docker " + strings.TrimSpace(string(version))

	fmt.Println("Building Phase 1 environment...")
	if err := r.dockerStream(ctx, "build", "-t", imageName, "-f",
		filepath.Join(root, "environment", "Dockerfile"), root); err != nil {
		return fmt.Errorf("build environment image: %w", err)
	}

	fmt.Println("Creating isolated graphical environment...")
	_, err = r.docker(ctx,
		"create",
		"--name", r.containerName,
		"--init",
		"--network=none",
		"--read-only",
		"--tmpfs=/tmp:rw,nosuid,nodev,size=64m",
		"--cap-drop=ALL",
		"--security-opt=no-new-privileges",
		"--pids-limit=128",
		"--memory=512m",
		"--cpus=1",
		imageName,
	)
	if err != nil {
		return fmt.Errorf("create environment: %w", err)
	}
	r.containerMade = true
	if _, err := r.docker(ctx, "start", r.containerName); err != nil {
		return fmt.Errorf("start environment: %w", err)
	}
	if err := r.waitFor(ctx, 10*time.Second, func() bool {
		_, readyErr := r.docker(ctx, "exec", r.containerName, "test", "-f", "/tmp/agentbox-ready")
		return readyErr == nil
	}); err != nil {
		return fmt.Errorf("wait for graphical environment: %w", err)
	}

	fmt.Println("Launching graphical mover demo...")
	if _, err := r.docker(ctx, "exec", "-d", r.containerName, "sh", "-c",
		"exec /opt/agentbox/mover >/tmp/stdout.log 2>/tmp/stderr.log"); err != nil {
		return fmt.Errorf("launch demo: %w", err)
	}

	var windowID string
	if err := r.waitFor(ctx, 10*time.Second, func() bool {
		output, searchErr := r.docker(ctx, "exec", r.containerName, "xdotool",
			"search", "--onlyvisible", "--name", "Agentbox Mover")
		if searchErr != nil {
			return false
		}
		windowID = strings.TrimSpace(strings.Split(string(output), "\n")[0])
		return windowID != ""
	}); err != nil {
		return fmt.Errorf("wait for demo window: %w", err)
	}
	if _, err := r.docker(ctx, "exec", r.containerName, "xdotool",
		"windowactivate", "--sync", windowID); err != nil {
		return fmt.Errorf("focus demo window: %w", err)
	}

	beforePath := filepath.Join(r.runDir, "screenshots", "before.png")
	fmt.Println("Capturing screenshot before input...")
	if err := r.screenshot(ctx, "/tmp/before.png", beforePath); err != nil {
		return err
	}
	before, err := squareCentroid(beforePath)
	if err != nil {
		return fmt.Errorf("inspect before screenshot: %w", err)
	}
	r.record.Before = &before

	fmt.Println("Sending synthetic mouse input...")
	if _, err := r.docker(ctx, "exec", r.containerName, "xdotool",
		"mousemove", "--window", windowID, "100", "100", "mousedown", "1", "mouseup", "1"); err != nil {
		return fmt.Errorf("send mouse input: %w", err)
	}
	if err := r.trace(actionRecord{
		Timestamp: time.Now().UTC(), Type: "mouse_move", X: 100, Y: 100,
	}); err != nil {
		return err
	}
	if err := r.trace(actionRecord{
		Timestamp: time.Now().UTC(), Type: "mouse_down", Button: 1,
	}); err != nil {
		return err
	}
	if err := r.trace(actionRecord{
		Timestamp: time.Now().UTC(), Type: "mouse_up", Button: 1,
	}); err != nil {
		return err
	}

	fmt.Println("Holding RIGHT for one second...")
	if _, err := r.docker(ctx, "exec", r.containerName, "xdotool", "keydown", "Right"); err != nil {
		return fmt.Errorf("send key down: %w", err)
	}
	if err := r.trace(actionRecord{
		Timestamp: time.Now().UTC(), Type: "key_down", Key: "RIGHT",
	}); err != nil {
		return err
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(time.Second):
	}
	if _, err := r.docker(ctx, "exec", r.containerName, "xdotool", "keyup", "Right"); err != nil {
		return fmt.Errorf("send key up: %w", err)
	}
	if err := r.trace(actionRecord{
		Timestamp: time.Now().UTC(), Type: "key_up", Key: "RIGHT", Duration: "1s",
	}); err != nil {
		return err
	}
	time.Sleep(100 * time.Millisecond)

	afterPath := filepath.Join(r.runDir, "screenshots", "after.png")
	fmt.Println("Capturing screenshot after input...")
	if err := r.screenshot(ctx, "/tmp/after.png", afterPath); err != nil {
		return err
	}
	after, err := squareCentroid(afterPath)
	if err != nil {
		return fmt.Errorf("inspect after screenshot: %w", err)
	}
	r.record.After = &after
	r.record.MovementPixels = after.X - before.X
	if r.record.MovementPixels < 100 {
		return fmt.Errorf("visual verification failed: square moved %.1f pixels right, want at least 100", r.record.MovementPixels)
	}

	fmt.Printf("Verified: square moved %.1f pixels to the right.\n", r.record.MovementPixels)
	fmt.Printf("Phase 1 passed. Artifacts: %s\n", runDir)
	return nil
}

func findRoot() (string, error) {
	current, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("get working directory: %w", err)
	}
	for {
		data, readErr := os.ReadFile(filepath.Join(current, "go.mod"))
		if readErr == nil && bytes.Contains(data, []byte("module agentbox")) {
			return current, nil
		}
		parent := filepath.Dir(current)
		if parent == current {
			return "", errors.New("run from the agentbox module directory")
		}
		current = parent
	}
}

func runID() (string, error) {
	random := make([]byte, 3)
	if _, err := rand.Read(random); err != nil {
		return "", err
	}
	return time.Now().UTC().Format("20060102T150405") + "-" + hex.EncodeToString(random), nil
}

func (r *runner) waitFor(ctx context.Context, timeout time.Duration, check func() bool) error {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		if check() {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-timer.C:
			return errors.New("timed out")
		case <-ticker.C:
		}
	}
}

func (r *runner) screenshot(ctx context.Context, containerPath, hostPath string) error {
	if _, err := r.docker(ctx, "exec", r.containerName, "scrot", "-o", containerPath); err != nil {
		return fmt.Errorf("capture screenshot: %w", err)
	}
	if err := r.extract(ctx, containerPath, hostPath); err != nil {
		return fmt.Errorf("extract screenshot: %w", err)
	}
	return nil
}

func (r *runner) extract(ctx context.Context, containerPath, hostPath string) error {
	data, err := r.docker(ctx, "exec", r.containerName, "cat", containerPath)
	if err != nil {
		return err
	}
	if err := os.WriteFile(hostPath, data, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", hostPath, err)
	}
	return nil
}

func squareCentroid(path string) (point, error) {
	file, err := os.Open(path)
	if err != nil {
		return point{}, err
	}
	defer file.Close()
	img, err := png.Decode(file)
	if err != nil {
		return point{}, err
	}

	var sumX, sumY, count uint64
	bounds := img.Bounds()
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			red, green, blue, _ := img.At(x, y).RGBA()
			if green > 0xc000 && red < 0x4000 && blue < 0x8000 {
				sumX += uint64(x)
				sumY += uint64(y)
				count++
			}
		}
	}
	if count < 1000 {
		return point{}, fmt.Errorf("found only %d green square pixels", count)
	}
	return point{
		X: float64(sumX) / float64(count),
		Y: float64(sumY) / float64(count),
	}, nil
}

func (r *runner) trace(action actionRecord) error {
	encoded, err := json.Marshal(action)
	if err != nil {
		return fmt.Errorf("encode action: %w", err)
	}
	if _, err := r.actions.Write(append(encoded, '\n')); err != nil {
		return fmt.Errorf("write action trace: %w", err)
	}
	return nil
}

func (r *runner) cleanup() error {
	if r.actions != nil {
		_ = r.actions.Close()
	}
	if !r.containerMade {
		return nil
	}

	fmt.Println("Stopping environment...")
	stopCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	for _, name := range []string{"stdout.log", "stderr.log"} {
		_ = r.extract(stopCtx, "/tmp/"+name, filepath.Join(r.runDir, name))
	}
	_, stopErr := r.docker(stopCtx, "stop", "--time=3", r.containerName)
	_, removeErr := r.docker(stopCtx, "rm", "-f", r.containerName)
	if stopErr != nil {
		return fmt.Errorf("stop environment: %w", stopErr)
	}
	if removeErr != nil {
		return fmt.Errorf("remove environment: %w", removeErr)
	}
	fmt.Println("Environment stopped cleanly.")
	return nil
}

func (r *runner) writeRecord() error {
	data, err := json.MarshalIndent(r.record, "", "  ")
	if err != nil {
		return fmt.Errorf("encode run record: %w", err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(filepath.Join(r.runDir, "run.json"), data, 0o644); err != nil {
		return fmt.Errorf("write run record: %w", err)
	}
	return nil
}

func (r *runner) docker(ctx context.Context, args ...string) ([]byte, error) {
	command := exec.CommandContext(ctx, "docker", args...)
	output, err := command.CombinedOutput()
	if err != nil {
		return output, fmt.Errorf("docker %s: %w: %s", args[0], err, strings.TrimSpace(string(output)))
	}
	return output, nil
}

func (r *runner) dockerStream(ctx context.Context, args ...string) error {
	command := exec.CommandContext(ctx, "docker", args...)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("docker %s: %w", strconv.Quote(strings.Join(args, " ")), err)
	}
	return nil
}

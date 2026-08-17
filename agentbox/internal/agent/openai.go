package agent

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"agentbox/internal/environment"
)

type OpenAIConfig struct {
	APIKey  string
	Model   string
	BaseURL string
	Client  *http.Client
}

type OpenAI struct {
	config OpenAIConfig
}

func NewOpenAI(config OpenAIConfig) (*OpenAI, error) {
	if config.APIKey == "" {
		return nil, errors.New("OPENAI_API_KEY is required for --agent openai")
	}
	if config.Model == "" {
		config.Model = "gpt-5"
	}
	if config.BaseURL == "" {
		config.BaseURL = "https://api.openai.com/v1"
	}
	if config.Client == nil {
		config.Client = &http.Client{Timeout: 90 * time.Second}
	}
	return &OpenAI{config: config}, nil
}

func (a *OpenAI) Name() string {
	return "openai:" + a.config.Model
}

func (a *OpenAI) NextAction(
	ctx context.Context,
	task string,
	history []Step,
	observation Observation,
) (Decision, error) {
	prompt, err := modelPrompt(task, history, observation)
	if err != nil {
		return Decision{}, err
	}
	requestBody := map[string]any{
		"model": a.config.Model,
		"input": []any{
			map[string]any{
				"role": "user",
				"content": []any{
					map[string]any{"type": "input_text", "text": prompt},
					map[string]any{
						"type": "input_image",
						"image_url": "data:image/png;base64," +
							base64.StdEncoding.EncodeToString(observation.Screenshot),
					},
				},
			},
		},
		"text": map[string]any{
			"format": map[string]any{
				"type":   "json_schema",
				"name":   "agentbox_action",
				"strict": true,
				"schema": decisionSchema(),
			},
		},
	}
	body, err := json.Marshal(requestBody)
	if err != nil {
		return Decision{}, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost,
		strings.TrimRight(a.config.BaseURL, "/")+"/responses", bytes.NewReader(body))
	if err != nil {
		return Decision{}, err
	}
	request.Header.Set("Authorization", "Bearer "+a.config.APIKey)
	request.Header.Set("Content-Type", "application/json")

	response, err := a.config.Client.Do(request)
	if err != nil {
		return Decision{}, err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(io.LimitReader(response.Body, 4<<20))
	if err != nil {
		return Decision{}, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return Decision{}, fmt.Errorf("OpenAI response %s: %s",
			response.Status, strings.TrimSpace(string(responseBody)))
	}
	text, err := responseText(responseBody)
	if err != nil {
		return Decision{}, err
	}
	return parseModelDecision(text)
}

func modelPrompt(task string, history []Step, observation Observation) (string, error) {
	contextData := struct {
		Task            string                    `json:"task"`
		History         []Step                    `json:"history"`
		RecentLogs      []environment.LogEntry    `json:"recent_logs"`
		PreviousActions []environment.InputAction `json:"previous_actions"`
	}{
		Task:            task,
		History:         history,
		RecentLogs:      observation.Logs,
		PreviousActions: observation.PreviousActions,
	}
	data, err := json.Marshal(contextData)
	if err != nil {
		return "", err
	}
	return "You control an interactive Linux application from screenshots. " +
		"Choose exactly one safe input action, or mark done when the task is complete. " +
		"Use X11 key names such as RIGHT, Return, or Escape. Keep waits under 5000 ms.\n" +
		string(data), nil
}

func decisionSchema() map[string]any {
	actionProperties := map[string]any{
		"type": map[string]any{
			"type": "string",
			"enum": []string{
				string(environment.KeyDown), string(environment.KeyUp),
				string(environment.MouseMove), string(environment.MouseDown),
				string(environment.MouseUp), string(environment.Wait),
			},
		},
		"key":         map[string]any{"type": "string"},
		"x":           map[string]any{"type": "integer"},
		"y":           map[string]any{"type": "integer"},
		"button":      map[string]any{"type": "integer"},
		"duration_ms": map[string]any{"type": "integer"},
	}
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"properties": map[string]any{
			"reason": map[string]any{"type": "string"},
			"done":   map[string]any{"type": "boolean"},
			"action": map[string]any{
				"anyOf": []any{
					map[string]any{
						"type":                 "object",
						"additionalProperties": false,
						"properties":           actionProperties,
						"required": []string{
							"type", "key", "x", "y", "button", "duration_ms",
						},
					},
					map[string]any{"type": "null"},
				},
			},
		},
		"required": []string{"reason", "done", "action"},
	}
}

func responseText(data []byte) (string, error) {
	var response struct {
		Output []struct {
			Content []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
		} `json:"output"`
	}
	if err := json.Unmarshal(data, &response); err != nil {
		return "", fmt.Errorf("decode OpenAI response: %w", err)
	}
	for _, output := range response.Output {
		for _, content := range output.Content {
			if content.Type == "output_text" && content.Text != "" {
				return content.Text, nil
			}
		}
	}
	return "", errors.New("OpenAI response contained no output_text")
}

func parseModelDecision(text string) (Decision, error) {
	var result struct {
		Reason string `json:"reason"`
		Done   bool   `json:"done"`
		Action *struct {
			Type       environment.InputType `json:"type"`
			Key        string                `json:"key"`
			X          int                   `json:"x"`
			Y          int                   `json:"y"`
			Button     int                   `json:"button"`
			DurationMS int                   `json:"duration_ms"`
		} `json:"action"`
	}
	if err := json.Unmarshal([]byte(text), &result); err != nil {
		return Decision{}, fmt.Errorf("decode model decision: %w", err)
	}
	if result.Reason == "" {
		return Decision{}, errors.New("model decision requires reason")
	}
	if result.Done {
		return Decision{Reason: result.Reason, Done: true}, nil
	}
	if result.Action == nil {
		return Decision{}, errors.New("model decision requires action when not done")
	}
	if result.Action.DurationMS < 0 || result.Action.DurationMS > 5000 {
		return Decision{}, errors.New("model wait must be between 0 and 5000 ms")
	}
	action := environment.InputAction{
		Type:     result.Action.Type,
		Key:      result.Action.Key,
		X:        result.Action.X,
		Y:        result.Action.Y,
		Button:   result.Action.Button,
		Duration: time.Duration(result.Action.DurationMS) * time.Millisecond,
	}
	switch action.Type {
	case environment.KeyDown, environment.KeyUp, environment.MouseMove,
		environment.MouseDown, environment.MouseUp, environment.Wait:
	default:
		return Decision{}, fmt.Errorf("model returned unsupported action %q", action.Type)
	}
	return Decision{Reason: result.Reason, Action: &action}, nil
}

var _ Agent = (*OpenAI)(nil)

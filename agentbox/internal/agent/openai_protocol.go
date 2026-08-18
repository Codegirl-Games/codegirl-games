package agent

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"

	"agentbox/internal/environment"
)

type responsesRequest struct {
	Model string                `json:"model"`
	Input []responsesInput      `json:"input"`
	Text  responsesTextSettings `json:"text"`
}

type responsesInput struct {
	Role    string             `json:"role"`
	Content []responsesContent `json:"content"`
}

type responsesContent struct {
	Type     string `json:"type"`
	Text     string `json:"text,omitempty"`
	ImageURL string `json:"image_url,omitempty"`
}

type responsesTextSettings struct {
	Format responsesFormat `json:"format"`
}

type responsesFormat struct {
	Type   string         `json:"type"`
	Name   string         `json:"name"`
	Strict bool           `json:"strict"`
	Schema map[string]any `json:"schema"`
}

func buildResponsesRequest(
	model string,
	task string,
	history []Step,
	observation Observation,
) ([]byte, error) {
	prompt, err := modelPrompt(task, history, observation)
	if err != nil {
		return nil, err
	}
	request := responsesRequest{
		Model: model,
		Input: []responsesInput{{
			Role: "user",
			Content: []responsesContent{
				{Type: "input_text", Text: prompt},
				{
					Type: "input_image",
					ImageURL: "data:image/png;base64," +
						base64.StdEncoding.EncodeToString(observation.Screenshot),
				},
			},
		}},
		Text: responsesTextSettings{Format: responsesFormat{
			Type:   "json_schema",
			Name:   "agentbox_action",
			Strict: true,
			Schema: decisionSchema(),
		}},
	}
	return json.Marshal(request)
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
		"Choose exactly one allowed input action, or mark done when the task is complete. " +
		"Use logical key names such as RIGHT, ENTER, or ESCAPE. Keep waits under 5000 ms.\n" +
		string(data), nil
}

func decisionSchema() map[string]any {
	// Strict structured output requires every action property to be present,
	// even when a particular action ignores most of them.
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

func extractResponseText(data []byte) (string, error) {
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

type modelDecision struct {
	Reason string       `json:"reason"`
	Done   bool         `json:"done"`
	Action *modelAction `json:"action"`
}

type modelAction struct {
	Type       environment.InputType `json:"type"`
	Key        string                `json:"key"`
	X          int                   `json:"x"`
	Y          int                   `json:"y"`
	Button     int                   `json:"button"`
	DurationMS int                   `json:"duration_ms"`
}

func parseModelDecision(text string) (Decision, error) {
	var modelOutput modelDecision
	if err := json.Unmarshal([]byte(text), &modelOutput); err != nil {
		return Decision{}, fmt.Errorf("decode model decision: %w", err)
	}
	if modelOutput.Reason == "" {
		return Decision{}, errors.New("model decision requires reason")
	}
	if modelOutput.Done {
		return Decision{Reason: modelOutput.Reason, Done: true}, nil
	}
	if modelOutput.Action == nil {
		return Decision{}, errors.New("model decision requires action when not done")
	}
	if modelOutput.Action.DurationMS < 0 || modelOutput.Action.DurationMS > 5000 {
		return Decision{}, errors.New("model wait must be between 0 and 5000 ms")
	}
	action := environment.InputAction{
		Type:       modelOutput.Action.Type,
		Key:        modelOutput.Action.Key,
		X:          modelOutput.Action.X,
		Y:          modelOutput.Action.Y,
		Button:     modelOutput.Action.Button,
		DurationMS: modelOutput.Action.DurationMS,
	}
	switch action.Type {
	case environment.KeyDown, environment.KeyUp, environment.MouseMove,
		environment.MouseDown, environment.MouseUp, environment.Wait:
	default:
		return Decision{}, fmt.Errorf("model returned unsupported action %q", action.Type)
	}
	return Decision{Reason: modelOutput.Reason, Action: &action}, nil
}

package agent

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type OpenAIConfig struct {
	APIKey  string
	Model   string
	BaseURL string
	Client  *http.Client
}

// OpenAI adapts the Responses API to Agentbox's provider-neutral Agent
// contract. HTTP and wire-format details do not leak into the runtime.
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

func (openAI *OpenAI) Name() string {
	return "openai:" + openAI.config.Model
}

func (openAI *OpenAI) NextAction(
	ctx context.Context,
	task string,
	history []Step,
	observation Observation,
) (Decision, error) {
	requestBody, err := buildResponsesRequest(
		openAI.config.Model,
		task,
		history,
		observation,
	)
	if err != nil {
		return Decision{}, err
	}
	request, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		strings.TrimRight(openAI.config.BaseURL, "/")+"/responses",
		bytes.NewReader(requestBody),
	)
	if err != nil {
		return Decision{}, err
	}
	request.Header.Set("Authorization", "Bearer "+openAI.config.APIKey)
	request.Header.Set("Content-Type", "application/json")

	httpResponse, err := openAI.config.Client.Do(request)
	if err != nil {
		return Decision{}, err
	}
	defer httpResponse.Body.Close()

	responseBody, err := io.ReadAll(io.LimitReader(httpResponse.Body, 4<<20))
	if err != nil {
		return Decision{}, err
	}
	if httpResponse.StatusCode < 200 || httpResponse.StatusCode >= 300 {
		return Decision{}, fmt.Errorf(
			"OpenAI response %s: %s",
			httpResponse.Status,
			strings.TrimSpace(string(responseBody)),
		)
	}
	outputText, err := extractResponseText(responseBody)
	if err != nil {
		return Decision{}, err
	}
	return parseModelDecision(outputText)
}

var _ Agent = (*OpenAI)(nil)

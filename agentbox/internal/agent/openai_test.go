package agent

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"agentbox/internal/environment"
)

func TestOpenAISendsScreenshotAndParsesDecision(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/responses" {
			t.Errorf("path = %q, want /responses", request.URL.Path)
		}
		if request.Header.Get("Authorization") != "Bearer test-key" {
			t.Errorf("missing bearer token")
		}
		body, err := io.ReadAll(request.Body)
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(body), "data:image/png;base64,AQID") {
			t.Errorf("request does not contain screenshot data URL: %s", body)
		}
		response.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(response, `{
			"output":[{"content":[{"type":"output_text","text":"{\"reason\":\"move right\",\"done\":false,\"action\":{\"type\":\"key_down\",\"key\":\"RIGHT\",\"x\":0,\"y\":0,\"button\":0,\"duration_ms\":0}}"}]}]
		}`)
	}))
	defer server.Close()

	controller, err := NewOpenAI(OpenAIConfig{
		APIKey: "test-key", Model: "test-model", BaseURL: server.URL, Client: server.Client(),
	})
	if err != nil {
		t.Fatal(err)
	}
	decision, err := controller.NextAction(context.Background(), "move", nil, Observation{
		Screenshot: []byte{1, 2, 3},
	})
	if err != nil {
		t.Fatal(err)
	}
	if decision.Action == nil || decision.Action.Type != environment.KeyDown ||
		decision.Action.Key != "RIGHT" {
		t.Fatalf("decision = %#v", decision)
	}
}

func TestDecisionSchemaIsJSONSerializable(t *testing.T) {
	if _, err := json.Marshal(decisionSchema()); err != nil {
		t.Fatal(err)
	}
}

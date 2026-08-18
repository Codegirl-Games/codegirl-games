.PHONY: build demo demo-binary phase1 test

build:
	go build -o agentbox ./cmd/agentbox

demo-binary:
	./scripts/build_demo.sh

demo: build demo-binary
	./agentbox run ./examples/mover --task "Launch the application, move the character to the right, and describe what happened."

phase1:
	go run ./cmd/agentbox phase1

test:
	go test ./...

# Agentbox

This is a local technical spike for a programmable graphical Linux
environment. It proves that a controller can launch an ordinary GUI process
headlessly, observe pixels and logs, inject keyboard and mouse input, drive the
application through a replaceable agent, record a trace, and shut the
environment down.

The default agent is deterministic and requires no API credentials. One
optional OpenAI Responses adapter demonstrates screenshot + text model control.
This is still a local spike, not a cloud control plane or production sandbox.
See [the architecture decision](docs/architecture.md) for the choices and
security boundary.

## Requirements

- Linux
- Go 1.22 or newer
- Docker Engine with a running daemon
- permission to use Docker without an interactive `sudo` prompt

No X server, window manager, or C compiler is required on the host; those
dependencies are built into the container image.

## One-command demo

From this directory:

```sh
make demo
```

That one command:

1. builds the `agentbox` CLI and mover executable;
2. creates a restricted Xvfb/Openbox environment;
3. stages and launches the executable;
4. runs the deterministic observe/press/wait/release/observe loop;
5. records screenshots, actions, decisions, logs, and final status;
6. stops and removes the environment, including on failure or interruption.

The equivalent explicit commands are:

```sh
make build demo-binary
./agentbox run ./examples/mover \
  --task "Launch the application, move the character to the right, and describe what happened."
```

Flags can appear before or after the path.

## Run a private executable

Pass a prebuilt Linux executable:

```sh
./agentbox run ./path/to/application --task "Open the menu and click Settings."
```

For a directory, add `agentbox.json`:

```json
{
  "command": "game",
  "args": ["--windowed"],
  "env": {"EXAMPLE": "value"},
  "window_title": "My Game"
}
```

The command is resolved relative to the manifest. The current runtime is
Debian-based, so dynamically linked executables must have compatible libraries.

## Model agent

The model adapter is opt-in:

```sh
export OPENAI_API_KEY="..."
./agentbox run ./path/to/application \
  --task "Move the character right and report the result." \
  --agent openai \
  --model gpt-5
```

Each request contains the task, current screenshot, previous actions, step
history, and recent application logs. Strict structured output allows one
backend-neutral input action or completion. Use `--max-steps` to bound a run.
The environment itself still has no network access.

## Runs and inspection

```sh
./agentbox runs
./agentbox inspect <run-id>
```

Each run writes:

```text
.agentbox/runs/<run-id>/
├── run.json
├── actions.jsonl
├── steps.jsonl
├── screenshots/
│   ├── 0001.png
│   └── ...
├── stdout.log
└── stderr.log
```

`run.json` has `schema_version: "1"` plus task, application, agent, timestamps,
status, and step count. `steps.jsonl` records each observation reference, agent
message, and action. `actions.jsonl` is a compact action-only stream.

## Original environment proof

The visual centroid test from Phase 1 remains available:

```sh
make phase1
```

## Development checks

```sh
make test
go vet ./...
```

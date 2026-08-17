# Agentbox Phase 1

This is a local technical spike for a programmable graphical Linux
environment. It proves that a controller can launch an ordinary GUI process
headlessly, observe pixels, inject keyboard and mouse input, and shut the
environment down.

Phase 1 does not contain an LLM, model provider, cloud control plane, or
production sandbox. See [the architecture decision](docs/architecture.md) for
the choices and security boundary.

## Requirements

- Linux
- Go 1.22 or newer
- Docker Engine with a running daemon
- permission to use Docker without an interactive `sudo` prompt

No X server, window manager, or C compiler is required on the host; those
dependencies are built into the container image.

## Run the proof

From this directory:

```sh
make phase1
```

That one command:

1. builds the local environment image;
2. starts a restricted container with Xvfb and Openbox;
3. launches the mover application;
4. captures `before.png`;
5. moves and clicks the mouse;
6. holds the RIGHT key for one second;
7. captures `after.png`;
8. locates the green square in both images and fails unless it moved at least
   100 pixels right;
9. stops and removes the container, including on failure or interruption.

A passing run ends with output similar to:

```text
Capturing screenshot before input...
Sending synthetic mouse input...
Holding RIGHT for one second...
Capturing screenshot after input...
Verified: square moved 180.0 pixels to the right.
Phase 1 passed. Artifacts: .../.agentbox/runs/20260817T...
Stopping environment...
Environment stopped cleanly.
```

## Artifacts

Each run writes:

```text
.agentbox/runs/<run-id>/
├── run.json
├── actions.jsonl
├── screenshots/
│   ├── before.png
│   └── after.png
├── stdout.log
└── stderr.log
```

`run.json` contains the measured before/after centroids, movement distance,
container-engine version, timestamps, and pass/fail status. `actions.jsonl`
contains the backend-neutral input actions sent during this proof. Application
output is copied from the container before it is destroyed.

## Development checks

```sh
make test
go vet ./...
```

The future `agentbox run <path> --task ...` flow belongs to Phases 2 and 3.
This branch intentionally stops after proving the environment mechanism.

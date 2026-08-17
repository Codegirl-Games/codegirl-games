# Phase 1 architecture decision

Status: accepted for the local spike

## Decision

Run one application environment per Docker container. Inside the container:

- Xvfb provides a 640×480, 24-bit, in-memory X11 display.
- Openbox gives ordinary desktop windows focus and placement behavior.
- The application renders to that display without knowing it is headless.
- `scrot` captures the complete display as PNG.
- `xdotool` injects keyboard and mouse events through X11's XTEST extension.

The Go process on the host owns the lifecycle. It builds and creates the
container, starts the display, launches the application as a separate step,
captures images, sends input, copies artifacts out, and removes the container.
The first spike intentionally uses the Docker CLI as its narrow adapter rather
than adding a Docker SDK dependency.

```text
Go phase-1 runner
  |
  +-- Docker lifecycle and process execution
        |
        +-- Xvfb display :99
        |     |
        |     +-- Openbox
        |     +-- arbitrary X11 application
        |
        +-- scrot observation
        +-- xdotool keyboard/mouse input
```

This is the smallest stack that exercises a real desktop input and rendering
path. Xvfb is an X server backed by memory instead of display hardware.
`xdotool` synthesizes standard X11 input, so the demo is not instrumented with
a private control API. The verification reads the before and after PNGs and
checks that the green square's pixel centroid moved, rather than trusting
application state or logs.

## Why this instead of the alternatives

### X11/Xvfb rather than Wayland

Wayland deliberately gives clients less global authority. Synthetic input and
whole-desktop capture are compositor-mediated, so a Wayland implementation
would require selecting and configuring a headless compositor plus its
specific control protocol. That is a good future backend, but it adds no
evidence to this first question. Xvfb, XTEST, and framebuffer capture are
mature, software-only, and replaceable behind the later `Environment`
interface.

X11 is not a security boundary. Processes sharing one X server can generally
observe or affect one another. The design therefore uses one display and one
container per environment.

### No VNC/noVNC yet

VNC is useful for a human live viewer, but it is not needed for programmatic
screenshots or input. Adding an RFB server and browser client would introduce
more processes, ports, encoding, and latency without improving the Phase 1
proof. A later observer can attach x11vnc, or the display backend can become an
Xvnc server, without changing agent actions.

### Software rendering first

Xvfb does not provide a modern GPU. Many toolkit applications can use software
rendering, which is sufficient for this proof. GPU-heavy games may require a
different environment backend using headless DRM/EGL, a virtual GPU, or GPU
passthrough. That compatibility question is explicitly not answered by this
spike.

### A small Xlib demo rather than Raylib

The demo is C/Xlib so the image has only distribution packages and proves the
display/input mechanism directly. Raylib would make a nicer example but adds a
source or package dependency without changing the tested path. The runtime is
not coupled to Xlib: any executable in a future staged image can use SDL,
Raylib, Qt, GTK, a browser, or another X11-compatible toolkit.

## Separation preserved for later phases

Phase 1 contains concrete orchestration, but its data flow already keeps these
roles distinct:

```text
CLI -> lifecycle controller -> container environment -> application
                                      |
                                observation/input
                                      |
                              deterministic driver
```

Phase 2 should extract lifecycle, screenshot, input, and logs into an
`Environment` interface with backend-neutral actions. Phase 3 should consume
that interface through an `Agent`; neither a deterministic agent nor a model
adapter should import Docker or X11 details.

## Security boundary

The container flags reduce accidental damage: no network, read-only root
filesystem, a bounded tmpfs, a non-root user, all Linux capabilities dropped,
`no-new-privileges`, and CPU, memory, and PID limits. They are useful
defense-in-depth, not a production hostile-code sandbox.

Ordinary Docker containers share the host kernel. A kernel or container-runtime
escape can cross this boundary, resource-exhaustion controls are incomplete,
and image/build processing also handles attacker-controlled content. Do not run
arbitrary customer binaries with this spike on a valuable or multi-tenant
host.

Before production use, at minimum:

- put each untrusted workload behind a hardware-backed microVM boundary
  (Firecracker or Kata Containers), or evaluate gVisor where its syscall and
  graphics compatibility is sufficient;
- isolate image building from runtime hosts and verify limits on uploaded and
  expanded content;
- enforce outbound network policy, ephemeral storage quotas, wall-clock
  deadlines, and host-level CPU/memory/PID/I/O controls;
- use immutable, patched base images and a minimal guest kernel/filesystem;
- authenticate control operations and separate each tenant's artifacts,
  credentials, logs, and encryption keys;
- destroy the environment after every run and monitor the host boundary.

## Sources

- [X.Org Xvfb manual](https://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml)
- [xdotool project and XTEST behavior](https://github.com/jordansissel/xdotool)
- [Docker Engine security](https://docs.docker.com/engine/security/)
- [gVisor security model](https://gvisor.dev/docs/architecture_guide/security/)
- [Firecracker design](https://firecracker-microvm.github.io/)

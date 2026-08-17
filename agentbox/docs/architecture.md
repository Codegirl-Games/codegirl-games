# How Agentbox works

This document explains the prototype in simple terms. The exact technical names
are included in parentheses for readers who want to dig deeper.

## The big idea

Imagine giving a robot its own computer in a locked room.

The robot cannot look inside the program or use secret game controls. It can
only:

- look at the screen;
- press and release keyboard keys;
- move and click the mouse;
- read messages printed by the program.

Agentbox builds that room, starts the program, lets the robot interact with it,
and records everything that happened.

## The main parts

Each part has one job:

```text
You type a command
        |
        v
CLI: understands what you asked for
        |
        v
Runtime: runs the experiment step by step
       / \
      v   v
Environment       Agent
"the computer"    "the robot"
      |              |
      +------v-------+
             |
           Trace
     "the experiment notebook"
```

- **CLI:** The `agentbox` command you run in a terminal.
- **Runtime:** The referee. It asks the environment for a screenshot, gives it
  to the agent, carries out the agent's next action, and repeats.
- **Environment:** The temporary Linux computer containing the application.
- **Application:** The game or other interactive program being tested.
- **Agent:** The decision-maker. It can be a fixed test script or an AI model.
- **Trace:** The saved screenshots, actions, logs, and final result.

The important rule is that these parts do not cheat by reaching into each
other. The agent does not know about Docker or X11. The environment does not
know whether the agent is OpenAI, another model, or a fixed script.

## What happens during one run

When you run:

```sh
agentbox run ./my-game --task "Move the character right."
```

Agentbox does this:

1. Creates a fresh temporary room.
2. Copies the executable into that room.
3. Starts a pretend monitor inside the room.
4. Launches the application on that monitor.
5. Takes a screenshot.
6. Gives the screenshot, task, recent logs, and earlier actions to the agent.
7. Receives one action, such as `key_down RIGHT`.
8. Sends that action to the temporary computer.
9. Repeats until the agent says it is finished or reaches the step limit.
10. Saves the experiment and destroys the temporary room.

Stopping on errors is important. Even if the application or agent fails,
Agentbox still tries to save the logs and remove the environment.

## How the pretend computer works

The temporary room is a **Docker container**. A container is like a lightweight
box around a group of programs. It keeps files and processes separate enough
for this experiment, but it is not strong enough to safely hold a determined
attacker. The security section explains that limitation.

There is no physical monitor in the container, so we use a pretend one:

- **Xvfb** is a screen that exists only in memory. The application thinks it is
  drawing to a normal 640×480 monitor.
- **Openbox** acts like a tiny desktop. It puts windows in the right place and
  decides which window receives keyboard input.
- **scrot** takes a picture of the pretend monitor and saves it as a PNG.
- **xdotool** sends ordinary-looking keyboard and mouse events.

The application is not modified to accept special Agentbox commands. From its
point of view, a person pressed a key or clicked the mouse.

## Why use these old-looking tools?

### Why X11 instead of Wayland?

Linux has two common ways to manage graphical windows: X11 and Wayland.

Wayland is newer and safer for everyday desktops. One of its safety features is
that programs cannot freely spy on the whole screen or pretend to be the
keyboard. Those are exactly the powers Agentbox needs, so a headless Wayland
version would need more complicated, compositor-specific plumbing.

X11 already has small, well-understood tools for this experiment. Because all
X11 details are hidden behind the `Environment` interface, we can replace this
backend later without changing the agent.

One X11 screen is used per environment. Programs sharing an X11 screen can
interfere with each other, so unrelated runs must never share one.

### Why no VNC or browser viewer?

VNC would let a human watch the desktop live. That sounds useful, but the agent
only needs screenshots and input for now. Adding VNC would mean more servers,
network ports, and video encoding without proving anything new. It can be added
later as a viewer without changing how the agent thinks.

### What about a graphics card?

This version draws with the CPU instead of a GPU. That is enough for the simple
demo and many desktop applications. A demanding 3D game may need a future
environment that supplies a virtual or real GPU.

### Why is the demo written with Xlib?

The demo uses a tiny C/Xlib program because it has very few dependencies. It
proves the screen and input path directly. Agentbox is not tied to Xlib: a
staged application may use Raylib, SDL, Qt, GTK, a browser, or another toolkit
that can display through X11.

## Why the pieces are kept separate

Think about a toy car with replaceable batteries. The car should not care which
brand of battery powers it, and the battery should not need to know where the
car is driving.

Agentbox follows the same idea:

- The **Environment interface** is a remote control for a computer:
  `Start`, `Launch`, `Screenshot`, `SendInput`, `Logs`, and `Stop`.
- The **Agent interface** receives an observation and chooses the next action.
- The **Runtime** connects the two interfaces.

This lets us swap parts independently:

- Docker today could become a microVM or cloud machine later.
- X11 today could become a Wayland or GPU backend later.
- The fixed test agent could become OpenAI, Claude, Gemini, or a local model.
- The mover game could become a browser, drawing program, or other application.

Only `internal/environment/dockerx11` knows the current Linux tricks. Model
code never imports that package.

## The two current agents

### Deterministic agent

This is a fixed test script:

1. Look at the first screenshot.
2. Hold the RIGHT key.
3. Wait one second.
4. Check another screenshot.
5. Fail unless the green square moved at least 100 pixels.
6. Release the key and finish.

It is intentionally specific to the demo. Its purpose is to test the whole
system without paying for or depending on a model API.

### OpenAI adapter

This optional adapter sends the model:

- the user's task;
- the current screenshot;
- earlier actions;
- recent application logs;
- a short history of the run.

The model must return a small JSON object containing either one allowed action
or `done`. It cannot directly call Docker or run shell commands. The adapter is
one example, not a giant framework for every model company.

## How an application gets inside

`agentbox run` accepts a prebuilt Linux executable.

If the given path is a directory, an `agentbox.json` file says which executable
to run, what arguments to pass, which environment variables to set, and
optionally which window title to wait for.

Agentbox streams the executable into temporary memory inside the container. It
does not share the developer's whole folder with the container. The temporary
copy disappears when the run ends.

There is one practical limit: the executable and its libraries must work in the
Debian-based runtime image. Agentbox does not yet package missing libraries or
convert Windows and macOS programs.

## What gets recorded

The trace is an experiment notebook:

- `run.json` says what ran, which agent controlled it, and whether it finished;
- `steps.jsonl` records every observation, decision, and action in order;
- `actions.jsonl` is a smaller action-only list;
- `screenshots/` contains the pictures the agent saw;
- `stdout.log` and `stderr.log` contain application messages.

The trace format has a version number. Screenshots are separate files instead
of giant blobs inside JSON. This keeps traces easy to inspect and leaves room
for replay, comparisons, tests, or training data later.

## Is the container safe?

Not safe enough for strangers' programs.

Docker is more like a locked bedroom than a bank vault. It keeps ordinary
programs apart, but every container still shares the host's Linux kernel. A
serious kernel or Docker bug might let a hostile program break out.

This prototype adds useful guardrails:

- no network access inside the environment;
- a read-only main filesystem;
- a small, temporary writable area;
- an unprivileged user;
- no extra Linux capabilities;
- limits on CPU, memory, and process count;
- automatic destruction after the run.

These rules reduce accidents. They do not make Docker a trustworthy boundary
for arbitrary customer code. Do not use this prototype to run unknown binaries
on an important machine or a machine shared by multiple customers.

## What production would need

Before accepting untrusted uploads, the room needs walls built with hardware
virtualization. A small virtual machine, such as Firecracker or Kata
Containers, gives each run its own kernel. gVisor may be another option when it
supports the applications we need.

A real service would also need to:

- build uploaded programs away from runtime hosts;
- limit upload size, expanded file size, disk use, runtime, and network access;
- keep every customer's files, logs, secrets, and encryption keys separate;
- authenticate every control request;
- patch and replace base images regularly;
- monitor hosts and destroy every machine after its run.

## What this experiment proves

It proves the interaction model:

1. launch a normal graphical Linux application without a physical monitor;
2. observe it through screenshots and logs;
3. control it with keyboard and mouse actions;
4. keep the environment and agent replaceable;
5. save enough information to understand what happened;
6. shut everything down cleanly.

It does **not** prove production security, GPU game support, cloud scaling,
Windows/macOS support, billing, or authentication.

## Small glossary

- **Container:** A lightweight box around processes and files.
- **Backend:** One implementation hidden behind a common interface.
- **X11:** A Linux system for drawing windows and handling input.
- **Headless:** Running without a physical monitor.
- **Synthetic input:** Keyboard or mouse events created by software.
- **Trace:** The saved record of a run.
- **Kernel:** The deepest part of the operating system that controls hardware
  and processes.
- **MicroVM:** A small virtual machine with its own kernel.

## Sources

- [X.Org Xvfb manual](https://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml)
- [xdotool project and XTEST behavior](https://github.com/jordansissel/xdotool)
- [Docker Engine security](https://docs.docker.com/engine/security/)
- [gVisor security model](https://gvisor.dev/docs/architecture_guide/security/)
- [Firecracker design](https://firecracker-microvm.github.io/)

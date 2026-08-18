package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"agentbox/internal/phase1"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	var err error
	switch os.Args[1] {
	case "phase1":
		err = phase1.Run(ctx)
	case "run":
		err = run(ctx, os.Args[2:])
	case "runs":
		err = listRuns()
	case "inspect":
		err = inspect(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "agentbox: %v\n", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `usage:
  agentbox run <path> --task "<task>" [--agent deterministic|openai] [--model <model>]
  agentbox runs
  agentbox inspect <run-id>
  agentbox phase1`)
}

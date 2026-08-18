package main

import "testing"

func TestParseRunOptionsAllowsFlagsAfterPath(t *testing.T) {
	options, err := parseRunOptions([]string{
		"./game", "--task", "move right", "--max-steps=7",
	})
	if err != nil {
		t.Fatal(err)
	}
	if options.applicationPath != "./game" ||
		options.task != "move right" ||
		options.maxSteps != 7 {
		t.Fatalf("options = %#v", options)
	}
}

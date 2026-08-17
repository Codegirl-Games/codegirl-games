package dockerx11

import "testing"

func TestX11KeyTranslatesLogicalNames(t *testing.T) {
	tests := map[string]string{
		"RIGHT":  "Right",
		"LEFT":   "Left",
		"ENTER":  "Return",
		"ESCAPE": "Escape",
		"A":      "a",
	}
	for input, want := range tests {
		if got := x11Key(input); got != want {
			t.Errorf("x11Key(%q) = %q, want %q", input, got, want)
		}
	}
}

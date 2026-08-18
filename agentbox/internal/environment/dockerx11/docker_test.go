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
		if got := toX11KeyName(input); got != want {
			t.Errorf("toX11KeyName(%q) = %q, want %q", input, got, want)
		}
	}
}

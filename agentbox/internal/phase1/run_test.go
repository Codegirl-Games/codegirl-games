package phase1

import (
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestSquareCentroid(t *testing.T) {
	path := filepath.Join(t.TempDir(), "screenshot.png")
	img := image.NewRGBA(image.Rect(0, 0, 200, 100))
	green := color.RGBA{R: 0, G: 255, B: 102, A: 255}
	for y := 20; y < 60; y++ {
		for x := 80; x < 120; x++ {
			img.Set(x, y, green)
		}
	}
	writePNG(t, path, img)

	got, err := squareCentroid(path)
	if err != nil {
		t.Fatalf("squareCentroid() error = %v", err)
	}
	if got.X != 99.5 || got.Y != 39.5 {
		t.Fatalf("squareCentroid() = (%.1f, %.1f), want (99.5, 39.5)", got.X, got.Y)
	}
}

func TestSquareCentroidRejectsMissingSquare(t *testing.T) {
	path := filepath.Join(t.TempDir(), "empty.png")
	writePNG(t, path, image.NewRGBA(image.Rect(0, 0, 200, 100)))

	if _, err := squareCentroid(path); err == nil {
		t.Fatal("squareCentroid() error = nil, want missing-square error")
	}
}

func writePNG(t *testing.T, path string, img image.Image) {
	t.Helper()
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(file, img); err != nil {
		_ = file.Close()
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
}

package store

import (
	"testing"
	"time"

	"github.com/DavutHaxor/dockyard/daemon/internal/metrics"
)

func sample(second int) metrics.Sample {
	return metrics.Sample{Timestamp: time.Unix(int64(second), 0), CPUPercent: float64(second)}
}

func TestStoreWindow(t *testing.T) {
	s := New(2)
	if _, ok := s.Latest(); ok {
		t.Fatal("Latest() on empty store returned ok")
	}
	if history := s.History(0); len(history) != 0 || history == nil {
		t.Fatalf("History() on empty store = %v", history)
	}

	s.Add(sample(1))
	s.Add(sample(2))
	s.Add(sample(3))

	latest, ok := s.Latest()
	if !ok || latest.CPUPercent != 3 {
		t.Fatalf("Latest() = %+v, %v", latest, ok)
	}
	history := s.History(0)
	if len(history) != 2 || history[0].CPUPercent != 2 || history[1].CPUPercent != 3 {
		t.Fatalf("History() = %+v", history)
	}

	limited := s.History(1)
	if len(limited) != 1 || limited[0].CPUPercent != 3 {
		t.Fatalf("History(1) = %+v", limited)
	}
}

func TestStoreCapacityFloor(t *testing.T) {
	s := New(0)
	s.Add(sample(1))
	s.Add(sample(2))
	if got := s.History(0); len(got) != 1 || got[0].CPUPercent != 2 {
		t.Fatalf("History() = %+v", got)
	}
}

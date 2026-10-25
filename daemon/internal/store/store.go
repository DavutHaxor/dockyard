// Package store keeps a bounded in-memory window of metric samples.
package store

import (
	"sync"

	"github.com/DavutHaxor/dockyard/daemon/internal/metrics"
)

// Store is a concurrency-safe ring of samples. It is intentionally not
// persistent: Dockyard only displays the current state and a short window.
type Store struct {
	mu       sync.RWMutex
	capacity int
	samples  []metrics.Sample
}

// New creates a store that keeps at most capacity samples.
func New(capacity int) *Store {
	if capacity < 1 {
		capacity = 1
	}
	return &Store{capacity: capacity}
}

// Add appends a sample, dropping the oldest when the buffer is full.
func (s *Store) Add(sample metrics.Sample) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.samples) < s.capacity {
		s.samples = append(s.samples, sample)
		return
	}
	copy(s.samples, s.samples[1:])
	s.samples[len(s.samples)-1] = sample
}

// Latest returns the most recent sample.
func (s *Store) Latest() (metrics.Sample, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if len(s.samples) == 0 {
		return metrics.Sample{}, false
	}
	return s.samples[len(s.samples)-1], true
}

// History returns up to limit samples in chronological order. A non-positive
// limit returns the whole window.
func (s *Store) History(limit int) []metrics.Sample {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if len(s.samples) == 0 {
		return []metrics.Sample{}
	}
	if limit <= 0 || limit > len(s.samples) {
		limit = len(s.samples)
	}
	out := make([]metrics.Sample, limit)
	copy(out, s.samples[len(s.samples)-limit:])
	return out
}

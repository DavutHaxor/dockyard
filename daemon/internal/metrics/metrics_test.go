package metrics

import (
	"os"
	"path/filepath"
	"testing"
)

const statFirst = `cpu  100 0 50 850 0 0 0 0 0 0
cpu0 50 0 25 425 0 0 0 0 0 0
cpu1 50 0 25 425 0 0 0 0 0 0
intr 123456 0 0
`

const statSecond = `cpu  850 0 50 1100 0 0 0 0 0 0
cpu0 425 0 25 550 0 0 0 0 0 0
cpu1 425 0 25 550 0 0 0 0 0 0
intr 223456 0 0
`

const meminfo = `MemTotal:       1000000 kB
MemFree:         100000 kB
MemAvailable:    250000 kB
Buffers:          20000 kB
Cached:          130000 kB
`

func writeProc(t *testing.T, dir string, files map[string]string) {
	t.Helper()
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
	}
}

func TestCollectorSample(t *testing.T) {
	proc := t.TempDir()
	writeProc(t, proc, map[string]string{
		"stat":    statFirst,
		"meminfo": meminfo,
		"uptime":  "12345.67 999.00\n",
		"loadavg": "0.52 0.48 0.44 1/100 1234\n",
	})

	collector := NewCollector(proc, t.TempDir())
	first, err := collector.Sample()
	if err != nil {
		t.Fatalf("Sample() error = %v", err)
	}
	if first.CPUCount != 2 {
		t.Errorf("CPUCount = %d, want 2", first.CPUCount)
	}
	if first.CPUPercent != 0 {
		t.Errorf("first CPUPercent = %v, want 0", first.CPUPercent)
	}
	if first.Memory.TotalBytes != 1000000*1024 {
		t.Errorf("Memory.TotalBytes = %d", first.Memory.TotalBytes)
	}
	if first.Memory.UsedBytes != 750000*1024 {
		t.Errorf("Memory.UsedBytes = %d", first.Memory.UsedBytes)
	}
	if first.Memory.Percent != 75 {
		t.Errorf("Memory.Percent = %v, want 75", first.Memory.Percent)
	}
	if first.UptimeSeconds != 12345.67 {
		t.Errorf("UptimeSeconds = %v", first.UptimeSeconds)
	}
	if first.Load1 != 0.52 || first.Load5 != 0.48 || first.Load15 != 0.44 {
		t.Errorf("loads = %v/%v/%v", first.Load1, first.Load5, first.Load15)
	}
	if first.Disk.TotalBytes == 0 {
		t.Error("Disk.TotalBytes = 0")
	}
	if first.Disk.Percent < 0 || first.Disk.Percent > 100 {
		t.Errorf("Disk.Percent = %v", first.Disk.Percent)
	}

	writeProc(t, proc, map[string]string{"stat": statSecond})
	second, err := collector.Sample()
	if err != nil {
		t.Fatalf("second Sample() error = %v", err)
	}
	if second.CPUPercent != 75 {
		t.Errorf("second CPUPercent = %v, want 75", second.CPUPercent)
	}
}

func TestParseMeminfoFallback(t *testing.T) {
	mem, err := parseMeminfo([]byte("MemTotal: 1000 kB\nMemFree: 100 kB\nBuffers: 50 kB\nCached: 50 kB\n"))
	if err != nil {
		t.Fatalf("parseMeminfo() error = %v", err)
	}
	if mem.AvailableBytes != 200*1024 || mem.UsedBytes != 800*1024 || mem.Percent != 80 {
		t.Errorf("unexpected memory: %+v", mem)
	}
}

func TestParseMeminfoMissingTotal(t *testing.T) {
	if _, err := parseMeminfo([]byte("MemFree: 100 kB\n")); err == nil {
		t.Fatal("parseMeminfo() error = nil, want error")
	}
}

func TestCollectorMissingFiles(t *testing.T) {
	collector := NewCollector(t.TempDir(), t.TempDir())
	if _, err := collector.Sample(); err == nil {
		t.Fatal("Sample() error = nil, want error")
	}
}

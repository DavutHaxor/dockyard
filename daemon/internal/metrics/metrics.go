// Package metrics reads the current system state from /proc and the
// filesystem. It intentionally keeps no history; the store owns the short
// in-memory window.
package metrics

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Sample is one point-in-time snapshot of the monitored host.
type Sample struct {
	Timestamp     time.Time `json:"timestamp"`
	CPUPercent    float64   `json:"cpu_percent"`
	CPUCount      int       `json:"cpu_count"`
	Load1         float64   `json:"load_1"`
	Load5         float64   `json:"load_5"`
	Load15        float64   `json:"load_15"`
	UptimeSeconds float64   `json:"uptime_seconds"`
	Memory        Memory    `json:"memory"`
	Disk          Disk      `json:"disk"`
}

// Memory is measured in bytes.
type Memory struct {
	TotalBytes     uint64  `json:"total_bytes"`
	UsedBytes      uint64  `json:"used_bytes"`
	AvailableBytes uint64  `json:"available_bytes"`
	Percent        float64 `json:"percent"`
}

// Disk is measured in bytes for the configured filesystem.
type Disk struct {
	Path       string  `json:"path"`
	TotalBytes uint64  `json:"total_bytes"`
	UsedBytes  uint64  `json:"used_bytes"`
	FreeBytes  uint64  `json:"free_bytes"`
	Percent    float64 `json:"percent"`
}

type cpuTimes struct {
	total uint64
	idle  uint64
}

// Collector samples the host. It remembers the previous CPU counters so that
// CPU usage can be calculated as a delta between calls.
type Collector struct {
	procPath string
	diskPath string

	mu   sync.Mutex
	prev *cpuTimes
}

// NewCollector creates a collector. procPath is normally /proc and diskPath is
// the filesystem to report on, normally /.
func NewCollector(procPath, diskPath string) *Collector {
	return &Collector{procPath: procPath, diskPath: diskPath}
}

// Sample reads all metrics. The first call reports 0% CPU because there is no
// previous counter to compare against.
func (c *Collector) Sample() (Sample, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	stat, err := os.ReadFile(filepath.Join(c.procPath, "stat"))
	if err != nil {
		return Sample{}, fmt.Errorf("read proc stat: %w", err)
	}
	cpu, cpuCount, err := parseStat(stat)
	if err != nil {
		return Sample{}, err
	}

	meminfo, err := os.ReadFile(filepath.Join(c.procPath, "meminfo"))
	if err != nil {
		return Sample{}, fmt.Errorf("read proc meminfo: %w", err)
	}
	mem, err := parseMeminfo(meminfo)
	if err != nil {
		return Sample{}, err
	}

	uptimeRaw, err := os.ReadFile(filepath.Join(c.procPath, "uptime"))
	if err != nil {
		return Sample{}, fmt.Errorf("read proc uptime: %w", err)
	}
	uptime, err := parseUptime(uptimeRaw)
	if err != nil {
		return Sample{}, err
	}

	loadRaw, err := os.ReadFile(filepath.Join(c.procPath, "loadavg"))
	if err != nil {
		return Sample{}, fmt.Errorf("read proc loadavg: %w", err)
	}
	load1, load5, load15, err := parseLoadavg(loadRaw)
	if err != nil {
		return Sample{}, err
	}

	disk, err := diskUsage(c.diskPath)
	if err != nil {
		return Sample{}, err
	}

	cpuPercent := 0.0
	if c.prev != nil {
		totalDelta := float64(cpu.total - c.prev.total)
		idleDelta := float64(cpu.idle - c.prev.idle)
		if totalDelta > 0 {
			cpuPercent = (1 - idleDelta/totalDelta) * 100
			cpuPercent = math.Max(0, math.Min(100, cpuPercent))
		}
	}
	c.prev = &cpu

	return Sample{
		Timestamp:     time.Now().UTC(),
		CPUPercent:    round(cpuPercent),
		CPUCount:      cpuCount,
		Load1:         load1,
		Load5:         load5,
		Load15:        load15,
		UptimeSeconds: uptime,
		Memory:        mem,
		Disk:          disk,
	}, nil
}

func parseStat(data []byte) (cpuTimes, int, error) {
	var (
		times cpuTimes
		count int
		found bool
	)

	for _, line := range strings.Split(string(data), "\n") {
		if line == "cpu" || strings.HasPrefix(line, "cpu ") {
			fields := strings.Fields(line)[1:]
			if len(fields) < 4 {
				return cpuTimes{}, 0, fmt.Errorf("parse proc stat: malformed cpu line")
			}
			var values [8]uint64
			for i := 0; i < len(fields) && i < len(values); i++ {
				v, err := strconv.ParseUint(fields[i], 10, 64)
				if err != nil {
					return cpuTimes{}, 0, fmt.Errorf("parse proc stat: %w", err)
				}
				values[i] = v
			}
			for _, v := range values {
				times.total += v
			}
			// idle + iowait
			times.idle = values[3] + values[4]
			found = true
			continue
		}
		if len(line) > 3 && strings.HasPrefix(line, "cpu") && line[3] >= '0' && line[3] <= '9' {
			count++
		}
	}

	if !found {
		return cpuTimes{}, 0, fmt.Errorf("parse proc stat: cpu line not found")
	}
	if count == 0 {
		count = 1
	}
	return times, count, nil
}

func parseMeminfo(data []byte) (Memory, error) {
	values := make(map[string]uint64)
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		key := strings.TrimSuffix(fields[0], ":")
		v, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			continue
		}
		// All meminfo values are in kB.
		values[key] = v * 1024
	}

	total, ok := values["MemTotal"]
	if !ok || total == 0 {
		return Memory{}, fmt.Errorf("parse proc meminfo: MemTotal missing")
	}
	available, ok := values["MemAvailable"]
	if !ok {
		available = values["MemFree"] + values["Buffers"] + values["Cached"]
	}
	if available > total {
		available = total
	}
	used := total - available
	return Memory{
		TotalBytes:     total,
		UsedBytes:      used,
		AvailableBytes: available,
		Percent:        round(percent(used, total)),
	}, nil
}

func parseUptime(data []byte) (float64, error) {
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return 0, fmt.Errorf("parse proc uptime: empty file")
	}
	v, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0, fmt.Errorf("parse proc uptime: %w", err)
	}
	return v, nil
}

func parseLoadavg(data []byte) (float64, float64, float64, error) {
	fields := strings.Fields(string(data))
	if len(fields) < 3 {
		return 0, 0, 0, fmt.Errorf("parse proc loadavg: expected 3 values")
	}
	var out [3]float64
	for i := range out {
		v, err := strconv.ParseFloat(fields[i], 64)
		if err != nil {
			return 0, 0, 0, fmt.Errorf("parse proc loadavg: %w", err)
		}
		out[i] = v
	}
	return out[0], out[1], out[2], nil
}

func diskUsage(path string) (Disk, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return Disk{}, fmt.Errorf("statfs %s: %w", path, err)
	}
	blockSize := uint64(stat.Bsize)
	total := stat.Blocks * blockSize
	free := stat.Bavail * blockSize
	used := (stat.Blocks - stat.Bfree) * blockSize
	return Disk{
		Path:       path,
		TotalBytes: total,
		UsedBytes:  used,
		FreeBytes:  free,
		Percent:    round(percent(used, used+free)),
	}, nil
}

func percent(part, total uint64) float64 {
	if total == 0 {
		return 0
	}
	return float64(part) / float64(total) * 100
}

func round(v float64) float64 {
	return math.Round(v*100) / 100
}

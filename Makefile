# All Flutter commands go through FVM. Never call bare `flutter`.
FLUTTER := fvm flutter

.PHONY: app-get app-run app-test app-analyze app-build app-clean \
        daemon-run daemon-test daemon-build daemon-fmt daemon-check

app-get:
	cd app && $(FLUTTER) pub get

app-run:
	cd app && $(FLUTTER) run -d linux

app-test:
	cd app && $(FLUTTER) test

app-analyze:
	cd app && $(FLUTTER) analyze

app-build:
	cd app && $(FLUTTER) build linux

app-clean:
	cd app && $(FLUTTER) clean

daemon-run:
	cd daemon && go run ./cmd/dockyardd

daemon-test:
	cd daemon && go test ./...

daemon-build:
	mkdir -p bin
	cd daemon && go build -o ../bin/dockyardd ./cmd/dockyardd

daemon-fmt:
	cd daemon && gofmt -w .

daemon-check:
	cd daemon && test -z "$$(gofmt -l .)" && go vet ./... && go test -race ./...

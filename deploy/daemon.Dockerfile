# syntax=docker/dockerfile:1

FROM golang:1.27-alpine AS build
WORKDIR /src

COPY daemon/go.mod daemon/go.sum ./
RUN go mod download

COPY daemon/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/dockyardd ./cmd/dockyardd

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/dockyardd /usr/local/bin/dockyardd

EXPOSE 8080
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/dockyardd"]

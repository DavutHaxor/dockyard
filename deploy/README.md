# Deployment

Everything needed to run the daemon on the monitored server.

Planned contents:

| Path | Purpose |
| --- | --- |
| `compose.yaml` | One-command self-hosting: daemon + reverse proxy |
| `daemon.Dockerfile` | Multi-stage build of `dockyardd` |
| `systemd/dockyard.service` | Native install alternative to Docker |
| `.env.example` | Auth token and port placeholders (real `.env` is ignored) |

## Security notes

- Mounting `/var/run/docker.sock` gives the container root-equivalent control of
  the host. Keep the daemon container minimal and never expose the socket.
- Set a strong admin token through the environment/secret, not in the image.
- Terminate TLS at a reverse proxy (Caddy or Traefik); keep `dockyardd` on the
  internal Docker network.
- The client connects to the proxy over HTTPS/WSS, never to the Docker socket.

The compose file and Dockerfile are added together with the daemon's first
runnable build.

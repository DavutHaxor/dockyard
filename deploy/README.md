# Deployment

Everything needed to run the daemon on the monitored server.

| Path | Purpose |
| --- | --- |
| `compose.yaml` | Recommended self-hosting setup |
| `daemon.Dockerfile` | Multi-stage, distroless image build |
| `.env.example` | Token, bind address, Docker socket GID |
| `systemd/dockyard.service` | Native install alternative |

## Docker Compose

```bash
cd deploy
cp .env.example .env
```

Edit `.env`:

- `DOCKYARD_ADMIN_TOKEN` — generate with `openssl rand -hex 32`.
- `DOCKER_GID` — `stat -c '%g' /var/run/docker.sock`. The image runs as
  nonroot; this supplementary group is how it reaches the socket.

```bash
docker compose up -d --build
docker compose ps
docker compose logs -f dockyard
curl http://127.0.0.1:8080/healthz
```

The build context is the repository root, so Compose must be run from `deploy/`
(or with `-f deploy/compose.yaml`).

### What the container gets

| Mount | Why |
| --- | --- |
| `/var/run/docker.sock` | Container list and control |
| `/proc` → `/host/proc` | Host CPU, memory, load, uptime |
| `/` → `/hostfs` | Host disk usage (read-only) |

Without the host `/proc` mount, metrics would describe the container's PID
namespace instead of the server. The compose file points
`DOCKYARD_PROC_PATH` and `DOCKYARD_DISK_PATH` at those mounts.

The root filesystem is read-only, all capabilities are dropped, and
`no-new-privileges` is set. The socket is the one privileged interface.

### Exposing it

The port is published on `127.0.0.1` by default. Keep it there until a TLS
reverse proxy is in front. Set `DOCKYARD_BIND=0.0.0.0` only when the proxy runs
elsewhere on the host or another machine, and firewall the port.

Caddy example (not yet a compose service):

```caddyfile
dockyard.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

Caddy proxies WebSocket upgrades automatically. The daemon deliberately has no
TLS listener of its own.

### Rootless Docker

With rootless Docker the socket lives in the user's runtime directory and has
different ownership. Point `DOCKYARD_DOCKER_HOST` at the mounted socket and
adjust `group_add`/`user` to match that user instead of using `DOCKER_GID`.

## systemd (native install)

```bash
cd ..
make daemon-build

sudo install -m 0755 bin/dockyardd /usr/local/bin/dockyardd
sudo useradd --system --no-create-home --shell /usr/sbin/nologin dockyard
sudo usermod -aG docker dockyard

sudo mkdir -p /etc/dockyard
sudo cp deploy/.env.example /etc/dockyard/dockyard.env
sudo chmod 0600 /etc/dockyard/dockyard.env
# Edit /etc/dockyard/dockyard.env: set the token, remove DOCKER_GID/DOCKYARD_BIND.

sudo cp deploy/systemd/dockyard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dockyard
```

Native installs read the host `/proc` and `/` directly, so the defaults for
`DOCKYARD_PROC_PATH` and `DOCKYARD_DISK_PATH` are correct.

## Security model

- **Docker socket access is root-equivalent.** Anyone who can talk to it can
  start a privileged container and take over the host. Treat the admin token and
  the daemon's HTTP port with the same care.
- **One admin, one token.** There are no roles or users by design. Use a long
  random token; rotate it by changing `DOCKYARD_ADMIN_TOKEN` and restarting
  (existing sessions are invalidated).
- **Sessions are short-lived JWTs** (default 12h). The admin token is only sent
  to `/api/v1/auth/login`.
- **TLS comes from a proxy.** Do not publish the daemon port to the internet.
- **No rate limiting yet.** Put login rate limits at the reverse proxy until one
  is added.

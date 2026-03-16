# Production-Ready Tor Proxy Container Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the tor-proxy into a production-ready, standalone container deployable via docker-compose or Kubernetes with proper process supervision, health checks, and security hardening.

**Architecture:** Replace the current bash-shell-as-PID-1 approach with s6-overlay as the process supervisor. All services (Tor instances, HAProxy, Privoxy) become supervised s6 services with proper lifecycle management. A sleep-loop service replaces cron for exit node rotation. The container exposes a health endpoint and runs services with minimal privileges.

**Tech Stack:** Docker (Ubuntu 24.04 LTS base), s6-overlay v3, Tor, HAProxy, Privoxy, docker-compose, shell scripting

---

## File Structure

```
tor-proxy/
├── Dockerfile                          # MODIFY - new base image, s6-overlay, multi-stage build
├── startup.sh                          # DELETE - replaced by s6 services
├── docker-compose.yml                  # CREATE - compose deployment
├── healthcheck.sh                      # CREATE - container health check script
├── configs/
│   ├── tor/
│   │   ├── torrc.template              # KEEP as-is
│   │   └── tor.list                    # MODIFY - update to noble (24.04)
│   └── haproxy/
│       └── haproxy.cfg                 # MODIFY - add backend health checks
├── s6-overlay/
│   └── s6-rc.d/
│       ├── init-config/
│       │   ├── type                    # CREATE - oneshot
│       │   ├── up                      # CREATE - generates tor configs + haproxy backends
│       │   └── dependencies.d/
│       │       └── base                # CREATE - empty marker
│       ├── tor/
│       │   ├── type                    # CREATE - longrun
│       │   ├── run                     # CREATE - runs all tor instances
│       │   ├── finish                  # CREATE - cleanup
│       │   └── dependencies.d/
│       │       └── init-config         # CREATE - depends on config generation
│       ├── haproxy/
│       │   ├── type                    # CREATE - longrun
│       │   ├── run                     # CREATE - runs haproxy in foreground
│       │   └── dependencies.d/
│       │       └── init-config         # CREATE - depends on config generation
│       ├── privoxy/
│       │   ├── type                    # CREATE - longrun
│       │   ├── run                     # CREATE - runs privoxy in foreground
│       │   └── dependencies.d/
│       │       └── init-config         # CREATE - depends on config generation
│       ├── tor-refresh/
│       │   ├── type                    # CREATE - longrun
│       │   ├── run                     # CREATE - sleep loop that sends SIGHUP
│       │   └── dependencies.d/
│       │       └── tor                 # CREATE - depends on tor running
│       └── user/
│           └── contents.d/
│               ├── init-config         # CREATE - empty marker
│               ├── tor                 # CREATE - empty marker
│               ├── haproxy             # CREATE - empty marker
│               ├── privoxy             # CREATE - empty marker
│               └── tor-refresh         # CREATE - empty marker
├── k8s/
│   ├── deployment.yaml                 # CREATE - Kubernetes deployment
│   └── service.yaml                    # CREATE - Kubernetes service
└── README.md                           # MODIFY - updated usage instructions
```

---

## Chunk 1: Base Image and Build Modernization

### Task 1: Update base image and apt sources

**Files:**
- Modify: `Dockerfile:1` (base image)
- Modify: `configs/tor/tor.list:1-2` (apt source codename)

- [ ] **Step 1: Update tor.list to use Ubuntu 24.04 (noble) codename**

Replace contents of `configs/tor/tor.list`:

```
deb     [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org noble main
deb-src [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org noble main
```

- [ ] **Step 2: Update Dockerfile base image and clean up build layer**

Replace the entire `Dockerfile` with:

```dockerfile
FROM ubuntu:24.04

ENV TOR_INSTANCES=3
ENV TOR_IP_REFRESH_INTERVAL=300

COPY configs/tor/tor.list /etc/apt/sources.list.d/tor.list

RUN apt-get update && \
    apt-get install -y --no-install-recommends gpg wget && \
    wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc \
      | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      tor deb.torproject.org-keyring haproxy privoxy gettext-base curl && \
    apt-get purge -y gpg wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

COPY configs/tor/torrc.template /etc/tor/torrc.template
COPY configs/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg

EXPOSE 8118
CMD ["/bin/bash"]
```

Notes:
- `TOR_IP_REFRESH_CRON` replaced by `TOR_IP_REFRESH_INTERVAL` (seconds) — cron is removed entirely later.
- `gpg` and `wget` are now installed and purged in the same layer (build-time only).
- `curl` added for health check.
- `--no-install-recommends` reduces image size.
- `CMD` is temporary — will be replaced by s6 ENTRYPOINT in Task 2.

- [ ] **Step 3: Build the image to verify packages install correctly**

Run: `docker build -t tor-proxy:test .`
Expected: Build completes without errors.

---

### Task 2: Add s6-overlay as process supervisor

**Files:**
- Modify: `Dockerfile` (add s6-overlay installation, change entrypoint)

- [ ] **Step 1: Add s6-overlay installation to Dockerfile**

Add after the apt-get RUN block, before the COPY lines:

```dockerfile
# Install s6-overlay
ARG S6_OVERLAY_VERSION=3.2.0.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && rm /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz && rm /tmp/s6-overlay-x86_64.tar.xz
```

- [ ] **Step 2: Replace CMD with s6 ENTRYPOINT**

Replace the bottom of the Dockerfile:

```dockerfile
EXPOSE 8118
ENTRYPOINT ["/init"]
```

- [ ] **Step 3: Build to verify s6-overlay installs**

Run: `docker build -t tor-proxy:test .`
Expected: Build completes. `/init` exists in the image.

---

## Chunk 2: s6 Service Definitions

### Task 3: Create the init-config oneshot service

This replaces the config-generation logic from `startup.sh`. It runs once at container start before any long-running services.

**Files:**
- Create: `s6-overlay/s6-rc.d/init-config/type`
- Create: `s6-overlay/s6-rc.d/init-config/up`
- Create: `s6-overlay/s6-rc.d/init-config/dependencies.d/base` (empty)
- Create: `s6-overlay/s6-rc.d/user/contents.d/init-config` (empty)

- [ ] **Step 1: Create the service type file**

`s6-overlay/s6-rc.d/init-config/type`:
```
oneshot
```

- [ ] **Step 2: Create the init-config up script**

`s6-overlay/s6-rc.d/init-config/up`:
```bash
#!/command/execlineb -P

foreground {
  /bin/bash -c "
    SOCKS_PORT=9060
    CONTROL_PORT=9061

    for i in $(seq 1 ${TOR_INSTANCES}); do
      export SOCKS_PORT CONTROL_PORT TOR_COUNT=$i
      envsubst < /etc/tor/torrc.template > /etc/tor/torrc.$i
      mkdir -p /var/lib/tor$i
      chown debian-tor:debian-tor /var/lib/tor$i
      chmod 700 /var/lib/tor$i
      echo \"    server tor$i 127.0.0.1:${SOCKS_PORT} check\" >> /etc/haproxy/haproxy.cfg
      SOCKS_PORT=$((CONTROL_PORT + 1))
      CONTROL_PORT=$((SOCKS_PORT + 1))
    done

    # Append SOCKS5 forwarding to privoxy config
    echo 'forward-socks5 / 127.0.0.1:1080 .' >> /etc/privoxy/config
    # Ensure privoxy listens on all interfaces
    sed -i 's/^listen-address  127.0.0.1:8118/listen-address  0.0.0.0:8118/' /etc/privoxy/config
  "
}
```

- [ ] **Step 3: Create dependency and bundle markers**

Create these as empty files:
- `s6-overlay/s6-rc.d/init-config/dependencies.d/base`
- `s6-overlay/s6-rc.d/user/contents.d/init-config`

- [ ] **Step 4: Add COPY to Dockerfile**

Add before the ENTRYPOINT line:

```dockerfile
COPY s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
```

---

### Task 4: Create tor longrun service

**Files:**
- Create: `s6-overlay/s6-rc.d/tor/type`
- Create: `s6-overlay/s6-rc.d/tor/run`
- Create: `s6-overlay/s6-rc.d/tor/finish`
- Create: `s6-overlay/s6-rc.d/tor/dependencies.d/init-config` (empty)
- Create: `s6-overlay/s6-rc.d/user/contents.d/tor` (empty)

- [ ] **Step 1: Create service type**

`s6-overlay/s6-rc.d/tor/type`:
```
longrun
```

- [ ] **Step 2: Create the tor run script**

`s6-overlay/s6-rc.d/tor/run`:
```bash
#!/bin/bash
exec 2>&1

# Start all tor instances
for file in /etc/tor/torrc.*; do
    [ -f "$file" ] || continue
    tor -f "$file" &
done

# Wait for any child to exit (s6 will restart us)
wait -n
```

- [ ] **Step 3: Create the finish script**

`s6-overlay/s6-rc.d/tor/finish`:
```bash
#!/bin/bash
killall tor 2>/dev/null || true
```

- [ ] **Step 4: Create dependency and bundle markers**

Create these as empty files:
- `s6-overlay/s6-rc.d/tor/dependencies.d/init-config`
- `s6-overlay/s6-rc.d/user/contents.d/tor`

---

### Task 5: Create haproxy longrun service

**Files:**
- Create: `s6-overlay/s6-rc.d/haproxy/type`
- Create: `s6-overlay/s6-rc.d/haproxy/run`
- Create: `s6-overlay/s6-rc.d/haproxy/dependencies.d/init-config` (empty)
- Create: `s6-overlay/s6-rc.d/user/contents.d/haproxy` (empty)

- [ ] **Step 1: Create service type**

`s6-overlay/s6-rc.d/haproxy/type`:
```
longrun
```

- [ ] **Step 2: Create the haproxy run script**

`s6-overlay/s6-rc.d/haproxy/run`:
```bash
#!/bin/bash
exec 2>&1
exec haproxy -f /etc/haproxy/haproxy.cfg -db
```

The `-db` flag runs haproxy in foreground (no daemon) — required for s6 supervision.

- [ ] **Step 3: Create dependency and bundle markers**

Create these as empty files:
- `s6-overlay/s6-rc.d/haproxy/dependencies.d/init-config`
- `s6-overlay/s6-rc.d/user/contents.d/haproxy`

---

### Task 6: Create privoxy longrun service

**Files:**
- Create: `s6-overlay/s6-rc.d/privoxy/type`
- Create: `s6-overlay/s6-rc.d/privoxy/run`
- Create: `s6-overlay/s6-rc.d/privoxy/dependencies.d/init-config` (empty)
- Create: `s6-overlay/s6-rc.d/user/contents.d/privoxy` (empty)

- [ ] **Step 1: Create service type**

`s6-overlay/s6-rc.d/privoxy/type`:
```
longrun
```

- [ ] **Step 2: Create the privoxy run script**

`s6-overlay/s6-rc.d/privoxy/run`:
```bash
#!/bin/bash
exec 2>&1
exec privoxy --no-daemon /etc/privoxy/config
```

`--no-daemon` keeps privoxy in foreground for s6 supervision.

- [ ] **Step 3: Create dependency and bundle markers**

Create these as empty files:
- `s6-overlay/s6-rc.d/privoxy/dependencies.d/init-config`
- `s6-overlay/s6-rc.d/user/contents.d/privoxy`

---

### Task 7: Create tor-refresh longrun service (replaces cron)

**Files:**
- Create: `s6-overlay/s6-rc.d/tor-refresh/type`
- Create: `s6-overlay/s6-rc.d/tor-refresh/run`
- Create: `s6-overlay/s6-rc.d/tor-refresh/dependencies.d/tor` (empty)
- Create: `s6-overlay/s6-rc.d/user/contents.d/tor-refresh` (empty)

- [ ] **Step 1: Create service type**

`s6-overlay/s6-rc.d/tor-refresh/type`:
```
longrun
```

- [ ] **Step 2: Create the refresh run script**

`s6-overlay/s6-rc.d/tor-refresh/run`:
```bash
#!/bin/bash
exec 2>&1

INTERVAL="${TOR_IP_REFRESH_INTERVAL:-300}"

while true; do
    sleep "$INTERVAL"
    echo "Refreshing Tor exit nodes..."
    killall -HUP tor 2>/dev/null || true
done
```

A simple sleep loop replaces cron entirely, using `TOR_IP_REFRESH_INTERVAL` env var (seconds).

- [ ] **Step 3: Create dependency and bundle markers**

Create these as empty files:
- `s6-overlay/s6-rc.d/tor-refresh/dependencies.d/tor`
- `s6-overlay/s6-rc.d/user/contents.d/tor-refresh`

---

## Chunk 3: HAProxy Health Checks and Container Health

### Task 8: Add backend health checks to HAProxy config

**Files:**
- Modify: `configs/haproxy/haproxy.cfg`

- [ ] **Step 1: Replace haproxy.cfg with health-check-enabled config**

```
global
    log stdout format raw local0
    maxconn 4096

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

listen socks5
    bind :1080
    mode tcp
    balance roundrobin
    option tcp-check
    default-server inter 10s fall 3 rise 2
```

Changes from original:
- Log to stdout (not syslog — better for containers)
- Removed `user/group haproxy` (s6 handles process ownership)
- Added `option tcp-check` and `default-server` with health check parameters
- The `check` keyword on each server line (added by init-config) enables per-backend health checking
- If a Tor instance goes down, HAProxy stops sending traffic after 3 failed checks

---

### Task 9: Add container health check

**Files:**
- Create: `healthcheck.sh`
- Modify: `Dockerfile` (add HEALTHCHECK directive)

- [ ] **Step 1: Create healthcheck.sh**

```bash
#!/bin/bash
curl -sf --connect-timeout 5 -x http://127.0.0.1:8118 http://check.torproject.org/api/ip > /dev/null 2>&1
```

This verifies end-to-end connectivity: Privoxy -> HAProxy -> Tor -> Internet.

- [ ] **Step 2: Add HEALTHCHECK to Dockerfile**

Add before ENTRYPOINT:

```dockerfile
COPY healthcheck.sh /scripts/healthcheck.sh
RUN chmod +x /scripts/healthcheck.sh

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
    CMD /scripts/healthcheck.sh
```

`start-period=120s` gives Tor time to bootstrap before health checks begin.

- [ ] **Step 3: Build and verify HEALTHCHECK is present**

Run: `docker build -t tor-proxy:test . && docker inspect tor-proxy:test | grep -A5 Healthcheck`
Expected: Shows healthcheck config in output.

---

## Chunk 4: Security Hardening

### Task 10: Ensure services run with minimal privileges

**Files:**
- Modify: `Dockerfile` (add user/group setup and directory permissions)

- [ ] **Step 1: Add user setup and permissions to Dockerfile**

Add after the apt-get RUN block, before s6 installation:

```dockerfile
RUN mkdir -p /run/haproxy /run/tor && \
    chown haproxy:haproxy /run/haproxy && \
    chown debian-tor:debian-tor /run/tor
```

Tor already drops to `debian-tor` by default when started as root. HAProxy drops to its own user via its global config. Privoxy drops via its own config. This step just ensures the runtime directories exist with correct ownership.

---

## Chunk 5: Deployment Manifests

### Task 11: Create docker-compose.yml

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Create docker-compose.yml**

```yaml
services:
  tor-proxy:
    build: .
    image: tor-proxy:latest
    container_name: tor-proxy
    ports:
      - "8118:8118"
    environment:
      - TOR_INSTANCES=3
      - TOR_IP_REFRESH_INTERVAL=300
    restart: unless-stopped
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - SETUID
      - SETGID
    tmpfs:
      - /tmp
      - /run
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

- [ ] **Step 2: Test with docker-compose**

Run: `docker compose up --build -d && sleep 5 && docker compose ps`
Expected: Container is running, status shows "Up" (health: starting).

---

### Task 12: Create Kubernetes manifests

**Files:**
- Create: `k8s/deployment.yaml`
- Create: `k8s/service.yaml`

- [ ] **Step 1: Create Kubernetes Deployment**

`k8s/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tor-proxy
  labels:
    app: tor-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tor-proxy
  template:
    metadata:
      labels:
        app: tor-proxy
    spec:
      containers:
        - name: tor-proxy
          image: tor-proxy:latest
          ports:
            - containerPort: 8118
              name: http-proxy
          env:
            - name: TOR_INSTANCES
              value: "3"
            - name: TOR_IP_REFRESH_INTERVAL
              value: "300"
          livenessProbe:
            exec:
              command:
                - /scripts/healthcheck.sh
            initialDelaySeconds: 120
            periodSeconds: 60
            timeoutSeconds: 15
            failureThreshold: 3
          readinessProbe:
            tcpSocket:
              port: 8118
            initialDelaySeconds: 30
            periodSeconds: 10
          resources:
            requests:
              memory: "256Mi"
              cpu: "250m"
            limits:
              memory: "512Mi"
              cpu: "500m"
```

- [ ] **Step 2: Create Kubernetes Service**

`k8s/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: tor-proxy
  labels:
    app: tor-proxy
spec:
  type: ClusterIP
  ports:
    - port: 8118
      targetPort: http-proxy
      protocol: TCP
      name: http
  selector:
    app: tor-proxy
```

- [ ] **Step 3: Validate manifests (if kubectl available)**

Run: `kubectl apply --dry-run=client -f k8s/`
Expected: `deployment.apps/tor-proxy created (dry run)` and `service/tor-proxy created (dry run)`

---

## Chunk 6: Cleanup and Documentation

### Task 13: Remove old startup.sh and finalize Dockerfile

**Files:**
- Delete: `startup.sh`
- Modify: `Dockerfile` (final form)

- [ ] **Step 1: Delete startup.sh**

Remove the file — all its logic is now in `s6-overlay/s6-rc.d/init-config/up`.

- [ ] **Step 2: Verify final Dockerfile**

The complete Dockerfile should be:

```dockerfile
FROM ubuntu:24.04

ENV TOR_INSTANCES=3
ENV TOR_IP_REFRESH_INTERVAL=300

COPY configs/tor/tor.list /etc/apt/sources.list.d/tor.list

RUN apt-get update && \
    apt-get install -y --no-install-recommends gpg wget && \
    wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc \
      | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      tor deb.torproject.org-keyring haproxy privoxy gettext-base curl && \
    apt-get purge -y gpg wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Ensure runtime directories exist with correct ownership
RUN mkdir -p /run/haproxy /run/tor && \
    chown haproxy:haproxy /run/haproxy && \
    chown debian-tor:debian-tor /run/tor

# Install s6-overlay
ARG S6_OVERLAY_VERSION=3.2.0.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && rm /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz && rm /tmp/s6-overlay-x86_64.tar.xz

# Copy configs
COPY configs/tor/torrc.template /etc/tor/torrc.template
COPY configs/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg

# Copy s6 service definitions
COPY s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d

# Health check
COPY healthcheck.sh /scripts/healthcheck.sh
RUN chmod +x /scripts/healthcheck.sh

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
    CMD /scripts/healthcheck.sh

EXPOSE 8118

ENTRYPOINT ["/init"]
```

- [ ] **Step 3: Full integration test**

```bash
docker compose up --build -d
# Wait for Tor to bootstrap (~2 minutes)
sleep 120
docker compose ps
curl -sf -x http://127.0.0.1:8118 https://check.torproject.org/api/ip
docker compose down
```

Expected: Container is healthy, curl returns JSON with a Tor exit IP.

---

### Task 14: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README with updated usage**

```markdown
# tor-proxy

A container-based HTTP proxy that routes traffic through multiple Tor instances with automatic load balancing and exit node rotation.

## Architecture

- **Tor** — Multiple instances for parallel anonymized connections
- **HAProxy** — TCP load balancer distributing SOCKS5 traffic across Tor instances with health checks
- **Privoxy** — HTTP-to-SOCKS5 protocol converter
- **s6-overlay** — Process supervisor ensuring all services stay running

## Quick Start

### Docker Compose (recommended)

```bash
docker compose up -d
```

Wait ~2 minutes for Tor to bootstrap, then test:

```bash
curl -x http://127.0.0.1:8118 https://check.torproject.org/api/ip
```

### Docker Run

```bash
docker build -t tor-proxy .
docker run -d --name tor-proxy -p 8118:8118 tor-proxy
```

### Kubernetes

```bash
# Build and push image to your registry first
kubectl apply -f k8s/
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `TOR_INSTANCES` | `3` | Number of Tor instances to run |
| `TOR_IP_REFRESH_INTERVAL` | `300` | Seconds between Tor exit node rotation (SIGHUP) |

## Health Checks

The container includes a built-in health check that verifies end-to-end connectivity through the Tor network. It starts checking after 120 seconds (Tor bootstrap time) and runs every 60 seconds.
```

---

## Execution Order Summary

| Task | Dependency | Description |
|------|-----------|-------------|
| 1 | None | Update base image to Ubuntu 24.04 |
| 2 | Task 1 | Install s6-overlay |
| 3 | Task 2 | Create init-config oneshot service |
| 4 | Task 3 | Create tor longrun service |
| 5 | Task 3 | Create haproxy longrun service |
| 6 | Task 3 | Create privoxy longrun service |
| 7 | Task 4 | Create tor-refresh service |
| 8 | None | Update HAProxy config with health checks |
| 9 | Task 2 | Add container health check |
| 10 | Tasks 3-7 | Security hardening (directory permissions) |
| 11 | Tasks 1-10 | docker-compose.yml |
| 12 | Tasks 1-10 | Kubernetes manifests |
| 13 | Tasks 1-10 | Remove startup.sh, finalize Dockerfile |
| 14 | Task 13 | Update README |

Tasks 4, 5, 6 can be done in parallel. Tasks 11 and 12 can be done in parallel.

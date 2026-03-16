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

# Caddy + CrowdSec + Rate Limiting + Docker Proxy Setup

This repository provides a custom multi-stage Docker build for **Caddy** equipped with:
- **`caddy-docker-proxy`** (`github.com/lucaslorentz/caddy-docker-proxy/v2`): Automatically configures routes based on Docker container labels—**no Caddyfile required!**
- **`caddy-crowdsec-bouncer`** (`github.com/hslatman/caddy-crowdsec-bouncer`): Protects your services by enforcing CrowdSec ban decisions and optional AppSec WAF rules.
- **`caddy-ratelimit`** (`github.com/mholt/caddy-ratelimit`): Flexible rate limiting per host/IP zone directly via container labels.

---

## 🚀 How It Works (Zero-Caddyfile Architecture)

Instead of maintaining a static `Caddyfile`, **`caddy-docker-proxy`** monitors Docker container events via `/var/run/docker.sock` and generates Caddy's configuration dynamically in memory.

### 1. Global Options Configuration (In `docker-compose.yml`)
Global options (like global logging, CrowdSec LAPI connection, and execution order) are defined on the `caddy` service container using labels:

```yaml
labels:
  caddy_docker_proxy: "true"
  caddy.email: "you@example.com"
  
  # Log configuration (read by CrowdSec)
  caddy.log.output: "file /var/log/caddy/access.log"
  caddy.log.format: "json"
  caddy.log.level: "INFO"

  # Execution Order: Ensure CrowdSec and Rate Limiting execute before Reverse Proxying
  caddy.order.0: "crowdsec before rate_limit"
  caddy.order.1: "rate_limit before reverse_proxy"

  # CrowdSec LAPI Bouncer configuration
  caddy.crowdsec.api_url: "http://crowdsec:8080"
  caddy.crowdsec.api_key: "${CROWDSEC_BOUNCER_API_KEY}"
```

### 2. Protecting Application Services
To expose and protect any container (e.g. `whoami`, `wordpress`, `nextcloud`, etc.), simply attach `caddy` labels to that container:

```yaml
services:
  myapp:
    image: my-app:latest
    networks:
      - caddy_net
    labels:
      # Domain definition
      caddy: "app.example.com"

      # Enable CrowdSec Bouncer on this domain
      caddy.crowdsec: ""

      # Configure Rate Limiting (e.g., 20 requests per 10 seconds per IP)
      caddy.rate_limit.zone.myapp_limit.key: "{remote_host}"
      caddy.rate_limit.zone.myapp_limit.events: "20"
      caddy.rate_limit.zone.myapp_limit.window: "10s"

      # Proxy traffic to port 80 of this container
      caddy.reverse_proxy: "{{upstreams 80}}"
```

---

## 🛠 Setup & Deployment Instructions

### 1. Create External Docker Network
Ensure the shared proxy network exists:
```bash
docker network create caddy_net
```

### 2. Configure Environment Variables
Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

### 3. Build & Launch Containers
```bash
docker compose up -d --build
```

### 4. Generate CrowdSec Bouncer API Key
Once CrowdSec is running, create the bouncer key for Caddy:
```bash
docker exec -t crowdsec cscli bouncers add caddy-bouncer
```
Copy the generated key into your `.env` file (`CROWDSEC_BOUNCER_API_KEY=...`), then restart Caddy:
```bash
docker compose restart caddy
```

---

## 🔍 Verification Commands

- **Check Caddy generated configuration:**
  ```bash
  docker exec caddy caddy fmt /config/caddy/Caddyfile
  ```
- **View active CrowdSec bouncers:**
  ```bash
  docker exec crowdsec cscli bouncers list
  ```
- **Test Rate Limiting:**
  Run a burst test against your app:
  ```bash
  for i in {1..15}; do curl -i https://whoami.example.com; done
  ```
  Requests exceeding the limit will receive `HTTP/2 429 Too Many Requests`.

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
  caddy.order_0: "crowdsec before rate_limit"
  caddy.order_1: "rate_limit before reverse_proxy"

  # CrowdSec LAPI Bouncer configuration
  caddy.crowdsec.api_url: "http://crowdsec:8080"
  caddy.crowdsec.api_key: "${CROWDSEC_BOUNCER_API_KEY}"
```

### 2. Protecting Application Services
To expose and protect any container (e.g. `whoami`, `portainer`, `wordpress`, `nextcloud`, etc.), attach `caddy` labels to that container.

#### A. Basic Service Protection (Global Rate Limiting)
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
      caddy.rate_limit.zone: "myapp_limit"
      caddy.rate_limit.zone.key: "{remote_host}"
      caddy.rate_limit.zone.events: "20"
      caddy.rate_limit.zone.window: "10s"

      # Proxy traffic to port 80 of this container
      caddy.reverse_proxy: "{{upstreams 80}}"
```

#### B. Endpoint & Method Specific Rate Limiting (e.g. Login / Brute Force Protection)
To protect sensitive endpoints (such as `POST /api/auth*` or `POST /login`) against brute force attacks without throttling static assets (HTML/CSS/JS) or regular dashboard navigation, use the `match` subdirectives:

```yaml
services:
  portainer:
    image: portainer/portainer-ce:latest
    networks:
      - caddy_net
    labels:
      caddy: "portainer.example.com"
      caddy.crowdsec: ""

      # Rate limit ONLY POST requests to the login endpoint (5 attempts per minute)
      caddy.rate_limit.zone: "portainer_login"
      caddy.rate_limit.zone.match.path: "/api/auth*"
      caddy.rate_limit.zone.match.method: "POST"
      caddy.rate_limit.zone.key: "{remote_host}"
      caddy.rate_limit.zone.events: "5"
      caddy.rate_limit.zone.window: "1m"

      # Proxy traffic to internal container port
      caddy.reverse_proxy: "{{upstreams 9000}}"
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

### 3. CrowdSec Log Acquisition (`crowdsec-config/acquis.yaml`)
Ensure [crowdsec-config/acquis.yaml](file:///home/strangemint/docker-containers/caddy-crowdsec/crowdsec-config/acquis.yaml) exists so CrowdSec automatically monitors Caddy's JSON access logs:

```yaml
filenames:
  - /var/log/caddy/access.log
labels:
  type: caddy
```

> [!NOTE]
> If you add or modify `acquis.yaml` while the containers are already running, reload CrowdSec to apply the changes:
> ```bash
> docker compose restart crowdsec
> ```

### 4. Build & Launch Containers
```bash
docker compose up -d --build
```

### 5. Generate CrowdSec Bouncer API Key
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
- **Check CrowdSec log acquisition & parsing metrics:**
  ```bash
  docker exec crowdsec cscli metrics
  ```
- **Test Rate Limiting:**
  Run a burst test against your app:
  ```bash
  for i in {1..15}; do curl -i https://whoami.example.com; done
  ```
  Requests exceeding the limit will receive `HTTP/2 429 Too Many Requests`.

---

## 📊 Optional: Observability & Log Aggregator Stack

An optional monitoring stack is available in [`docker-compose.monitoring.yml`](file:///home/strangemint/docker-containers/caddy-crowdsec/docker-compose.monitoring.yml):
* **Grafana Loki**: Log aggregation backend for Caddy & CrowdSec logs.
* **Promtail**: Log shipper scraping structured JSON access logs from `./caddy_logs/access.log`.
* **Prometheus**: Metrics collector scraping Caddy (`:2019/metrics`) and CrowdSec (`:6060/metrics`).
* **Grafana**: Pre-provisioned dashboards for metrics and log exploration, routed automatically through Caddy with SSL.

### 1. Launch Monitoring Stack
```bash
# Start standalone alongside running Caddy stack:
docker compose -f docker-compose.monitoring.yml up -d

# Or start together with core stack:
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

### 2. Access Grafana
Navigate to `https://${GRAFANA_DOMAIN}` (default: `https://grafana.example.com`).
* Data sources (`Prometheus` and `Loki`) are pre-configured automatically.
* Recommended Grafana Dashboards to import via **Dashboards > Import**:
  * **Caddy Metrics Dashboard**: `13462`
  * **CrowdSec Official Dashboard**: `14620`
* Explore logs in Grafana **Explore** tab using query: `{job="caddy"}`.


# --- Global Build Arguments ---
ARG CADDY_VERSION=2
ARG PROXY_VERSION=v2.12.0
ARG BOUNCER_VERSION=v0.9.2

# --- Stage 1: Builder ---
FROM caddy:builder AS builder

ARG PROXY_VERSION
ARG BOUNCER_VERSION

# Enable automatic Go toolchain management
ENV GOTOOLCHAIN=auto

WORKDIR /app

# Build Caddy binary with plugins:
# - Use --replace to force gaissmai/bart@v0.25.0 for ipstore dependency
# - caddy-docker-proxy (Dynamic configuration via Docker container labels)
# - caddy-crowdsec-bouncer (CrowdSec LAPI bouncer and AppSec integration)
# - caddy-ratelimit (HTTP rate limiting middleware)
RUN xcaddy build \
    --output /usr/bin/caddy \
    --replace github.com/gaissmai/bart=github.com/gaissmai/bart@v0.25.0 \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2@${PROXY_VERSION} \
    --with github.com/hslatman/caddy-crowdsec-bouncer/appsec@${BOUNCER_VERSION} \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@${BOUNCER_VERSION} \
    --with github.com/hslatman/caddy-crowdsec-bouncer/layer4@${BOUNCER_VERSION} \
    --with github.com/mholt/caddy-ratelimit

# --- Stage 2: Final Image ---
FROM caddy:${CADDY_VERSION}-alpine

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata mailcap

# Copy compiled caddy binary from builder stage
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Start in docker-proxy mode by default
CMD ["caddy", "docker-proxy"]

# Image Metadata
LABEL org.opencontainers.image.title="caddy-crowdsec-ratelimit" \
      org.opencontainers.image.description="Caddy with caddy-docker-proxy, crowdsec bouncer, and rate limiting"

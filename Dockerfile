# ============================================================================
# Turnkey Multi-Service Containerized Deployment for Render
# Generated automatically by orchestrator.py
# ============================================================================

# --- STAGE 1: Builder ---
FROM golang:1.26-bookworm AS builder

WORKDIR /build
RUN mkdir -p /app/bin

# --- Service: shadow-room-backend ---
ARG SHADOW_ROOM_BACKEND_REPO=https://github.com/gurjotsingh1774/shadow-room-backend
RUN git clone --depth 1 ${SHADOW_ROOM_BACKEND_REPO} /build/shadow-room-backend \
    && cd /build/shadow-room-backend \
    && go mod download \
    && CGO_ENABLED=0 GOOS=linux go build -v -ldflags='-s -w' -o /app/bin/shadow-room ./cmd/server

# --- Service: secure-token-allocation-backend ---
ARG SECURE_TOKEN_ALLOCATION_BACKEND_REPO=https://github.com/gurjotsingh1774/secure-token-allocation-backend
RUN git clone --depth 1 ${SECURE_TOKEN_ALLOCATION_BACKEND_REPO} /build/secure-token-allocation-backend \
    && cd /build/secure-token-allocation-backend \
    && go mod download \
    && CGO_ENABLED=0 GOOS=linux go build -v -ldflags='-s -w' -o /app/bin/secure-token-allocation .

# --- STAGE 2: Production Runtime ---
FROM alpine:3.21

# Install runtime dependencies: Nginx, Supervisord, envsubst (gettext), curl, tzdata
RUN apk add --no-cache \
    nginx \
    supervisor \
    gettext \
    curl \
    ca-certificates \
    tzdata \
    bash

# Set up application directories
WORKDIR /app
RUN mkdir -p /app/bin /etc/supervisor/conf.d /etc/nginx/templates /run/nginx /var/log/supervisor /var/log/nginx /var/www/html

# Copy compiled binaries from builder stage
COPY --from=builder /app/bin/ /app/bin/
RUN chmod +x /app/bin/*

# Copy Nginx configuration template & static dashboard
COPY nginx/nginx.conf.template /etc/nginx/nginx.conf.template
COPY nginx/html/ /var/www/html/

# Copy Supervisord configuration
COPY supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Render assigns PORT dynamically (defaults to 10000 on Render)
ENV PORT=10000
EXPOSE 10000

# Launch through orchestrator entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]

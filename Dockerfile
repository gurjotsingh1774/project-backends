# ============================================================================
# Turnkey Multi-Service Deployment for Render
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
ARG SECURE_TOKEN_ALLOCATION_COMMIT=74c2031
RUN git clone ${SECURE_TOKEN_ALLOCATION_BACKEND_REPO} /build/secure-token-allocation-backend \
    && cd /build/secure-token-allocation-backend \
    && git checkout ${SECURE_TOKEN_ALLOCATION_COMMIT} \
    && go mod download \
    && CGO_ENABLED=0 GOOS=linux go build -v -ldflags='-s -w' -o /app/bin/secure-token-allocation .

# --- STAGE 2: Production Runtime ---
FROM alpine:3.21

RUN apk add --no-cache \
    nginx \
    supervisor \
    gettext \
    curl \
    ca-certificates \
    tzdata \
    bash

WORKDIR /app
RUN mkdir -p /app/bin /etc/supervisor/conf.d /etc/nginx/templates /run/nginx /var/log/supervisor /var/log/nginx /var/www/html

# Copy compiled binaries from builder
COPY --from=builder /app/bin/ /app/bin/
RUN chmod +x /app/bin/*

# Copy configuration templates & entrypoint
COPY nginx/nginx.conf.template /etc/nginx/nginx.conf.template
COPY nginx/html/ /var/www/html/
COPY supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV PORT=10000
EXPOSE 10000

ENTRYPOINT ["/app/entrypoint.sh"]

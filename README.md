# Turnkey Multi-Backend Orchestration System for Render

A production-ready orchestration framework to build, containerize, and deploy multiple backend services onto a **single Render Web Service** behind a unified **Nginx reverse proxy** managed by **Supervisord**.

---

## 🏛️ Architecture Overview

Render Web Services allocate a dynamic public ingress port via the environment variable `$PORT` (typically `10000`) and forward all external HTTP/WebSocket traffic to that single port.

This turnkey deployment solves the multi-service deployment challenge by combining:
1. **Dynamic Nginx Ingress**: Binds to `${PORT}` dynamically at container boot via `envsubst`, handles SSL termination offloaded by Render Edge, and routes traffic based on path prefixes with automatic route prefix stripping.
2. **WebSocket & SSE Protocol Support**: Native Nginx connection upgrading for full-duplex WebSockets and unbuffered streaming for Server-Sent Events (SSE).
3. **Supervisord Process Supervisor (PID 1)**: Concurrently orchestrates and monitors all internal microservices and Nginx, automatically restarting failed processes and streaming all standard and error logs directly to `/dev/stdout` and `/dev/stderr` for unified real-time visibility in the Render dashboard.
4. **Optimized Multi-Stage Docker Build**: Compiles pure static Go binaries in a build stage and packages them into a minimal, hardened Alpine Linux runtime image (< 70 MB) for fast deployments and minimal RAM consumption (comfortably fitting within Render's 512 MB memory constraints).

```
                      ┌─────────────────────────────────────────┐
                      │            Render Edge Router           │
                      └────────────────────┬────────────────────┘
                                           │ Public Traffic ($PORT)
                                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ Render Container (Single Instance)                                                     │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │                         Nginx Reverse Proxy (:10000)                           │   │
│   │                                                                                │   │
│   │  /healthz        ──> 200 OK (Render health checks & zero-downtime deploys)     │   │
│   │  /               ──> Dark-mode Service Status Dashboard & Documentation        │   │
│   │  /shadow-room/*  ──> Strips prefix ──> http://127.0.0.1:8081/* (WebSockets)   │   │
│   │  /secure-tokens/*──> Strips prefix ──> http://127.0.0.1:8082/* (SSE Streaming) │   │
│   └───────────────────────────────┬────────────────────────┬───────────────────────┘   │
│                                   │                        │                           │
│                                   ▼                        ▼                           │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │                        Supervisord Process Manager (PID 1)                     │   │
│   │                                                                                │   │
│   │  ┌───────────────────────────────┐          ┌───────────────────────────────┐  │   │
│   │  │   shadow-room-backend         │          │ secure-token-allocation       │  │   │
│   │  │   Go HTTP & WebSocket Server  │          │ Go Gin & GORM REST + SSE API  │  │   │
│   │  │   Internal Port: 8081         │          │ Internal Port: 8082           │  │   │
│   │  └───────────────┬───────────────┘          └───────────────┬───────────────┘  │   │
│   └──────────────────┼──────────────────────────────────────────┼──────────────────┘   │
└──────────────────────┼──────────────────────────────────────────┼──────────────────────┘
                       │                                          │
                       ▼                                          ▼
            ┌──────────────────────┐                   ┌──────────────────────┐
            │  Redis Store / Vault │                   │ PostgreSQL Database  │
            │  (Upstash / Render)  │                   │ (Render / Supabase)  │
            └──────────────────────┘                   └──────────────────────┘
```

---

## 📦 Services Specification

| Service Name | Source Repository | Public Route | Internal Port | Runtime | Protocols | External Dependencies |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`shadow-room-backend`** | [`gurjotsingh1774/shadow-room-backend`](https://github.com/gurjotsingh1774/shadow-room-backend) | `/shadow-room/` | `8081` | Go 1.24 (Static) | HTTP REST, WebSockets (`/ws`) | Redis (`VAULT_ADDRESS`) |
| **`secure-token-allocation-backend`** | [`gurjotsingh1774/secure-token-allocation-backend`](https://github.com/gurjotsingh1774/secure-token-allocation-backend) | `/secure-tokens/` | `8082` | Go 1.24 (Static) | HTTP REST, Server-Sent Events (SSE) | PostgreSQL (`DATABASE_URL`) |

---

## 🔀 Route Mapping & Prefix Stripping

Nginx intercepts incoming paths, strips the route prefix, and forwards the clean request to the appropriate internal backend:

| External Incoming URL | Internal Forwarded Destination | Features Enabled |
| :--- | :--- | :--- |
| `GET /healthz` | Direct Nginx Response `200 OK` | Uptime check for Render |
| `GET /` | Embedded Developer Status Dashboard | HTML5 UI |
| `POST /shadow-room/api/auth/register` | `http://127.0.0.1:8081/api/auth/register` | Prefix stripped, CORS |
| `GET /shadow-room/ws` | `http://127.0.0.1:8081/ws` | WebSocket Upgraded (`Upgrade: websocket`) |
| `GET /secure-tokens/api/health` | `http://127.0.0.1:8082/api/health` | Prefix stripped |
| `GET /secure-tokens/api/public/allocations/stream` | `http://127.0.0.1:8082/api/public/allocations/stream` | Unbuffered SSE (`proxy_buffering off`) |
| `POST /secure-tokens/api/admin/auth/login` | `http://127.0.0.1:8082/api/admin/auth/login` | Signed Cookie Auth |

*Missing trailing slashes (e.g. `/shadow-room`) are automatically redirected to canonical paths (`/shadow-room/`) with HTTP 301.*

---

## 🚀 Deployment to Render

### Method 1: 1-Click Infrastructure-as-Code via Blueprint (`render.yaml`) - *Recommended*

The included `render.yaml` automatically sets up the Web Service, creates a managed PostgreSQL database, and configures environment variables with cryptographically secure random values.

1. Push this repository to GitHub or GitLab.
2. In the [Render Dashboard](https://dashboard.render.com/):
   - Click **New +** > **Blueprint**.
   - Connect your repository.
   - Render will parse `render.yaml` and display the blueprint resources:
     - **Web Service**: `unified-backend-mesh` (Docker runtime)
     - **PostgreSQL Database**: `mesh-postgres` (Linked automatically via `DATABASE_URL`)
3. Set your Redis connection string for `VAULT_ADDRESS` (e.g., from [Upstash Redis](https://upstash.com/) or Render Redis):
   ```
   rediss://default:your-password@your-endpoint.upstash.io:6379
   ```
4. Click **Apply**. Render will build the Docker container and deploy the unified stack.

---

### Method 2: Manual Web Service Setup in Render Dashboard

1. In the [Render Dashboard](https://dashboard.render.com/), click **New +** > **Web Service**.
2. Connect your Git repository.
3. Configure the following settings:
   - **Name**: `unified-backend-mesh`
   - **Environment**: `Docker`
   - **Dockerfile Path**: `./Dockerfile`
   - **Docker Context**: `.`
   - **Health Check Path**: `/healthz`
   - **Plan**: `Starter` (or `Free`)
4. In the **Environment Variables** tab, copy the variables from `.env`.
5. Click **Create Web Service**.

---

## 🔑 Environment Variables Reference

| Variable | Target Service | Purpose | Value in `.env` |
| :--- | :--- | :--- | :--- |
| `PORT` | Nginx Gateway | Ingress port | `10000` (Render overrides automatically) |
| `AUTH_SECRET` | `shadow-room` | 256-bit cryptographic hex key for JWT verification | Pre-generated 64-char hex |
| `GRID_ORIGIN` | `shadow-room` | Allowed CORS origin domain | `https://app.yourdomain.com` |
| `HANDSHAKE_TTL_SECONDS` | `shadow-room` | Ticket lifetime in seconds | `60` |
| `VAULT_ADDRESS` | `shadow-room` | Redis connection URL | Dummy Upstash endpoint *(see notes below)* |
| `AES_KEY` | `secure-tokens`| 32-byte key for AES-256 PII encryption at rest | Pre-generated 32-char key |
| `SESSION_SECRET` | `secure-tokens`| 256-bit HMAC secret for admin cookies | Pre-generated 64-char hex |
| `QR_HMAC_SECRET` | `secure-tokens`| 256-bit HMAC secret for ticket QR code signatures | Pre-generated 64-char hex |
| `SUPER_ADMIN_USERNAME` | `secure-tokens`| Initial super administrator username | `admin` |
| `SUPER_ADMIN_PASSWORD` | `secure-tokens`| Initial super administrator password | Complex generated password |
| `DATABASE_URL` | `secure-tokens`| PostgreSQL connection string | Dummy Render Postgres URL *(see notes below)* |

---

## 📂 Deployment Directory Structure

```
project-backends/
├── Dockerfile                  # Multi-stage Dockerfile (builds Go binaries -> slim Alpine image)
├── entrypoint.sh               # Boot script: templates Nginx with $PORT and launches Supervisord
├── .env                        # Testing production-level environment file
├── render.yaml                 # Render Blueprint specification (Web Service + Postgres)
├── supervisor/
│   └── supervisord.conf        # Supervisord process manager config (PID 1)
├── nginx/
│   ├── nginx.conf.template     # Dynamic Nginx template with WebSocket/SSE reverse proxy
│   └── html/
│       └── index.html          # Embedded dark-mode status dashboard
└── README.md                   # System documentation
```

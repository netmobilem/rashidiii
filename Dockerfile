# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# TiTaN panel — single image that serves the API, the SSE stream, the
# subscription endpoint and the built SPA. Works on Railway, Fly, Docker and
# bare metal. No secrets are baked in: everything comes from the environment.
# ---------------------------------------------------------------------------

# ---- stage 1: build the frontend ------------------------------------------
FROM node:20-alpine AS frontend
WORKDIR /build
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund
COPY frontend/ ./
RUN npm run build

# ---- stage 2: python runtime ----------------------------------------------
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    TZ=UTC

# `curl` is needed by the healthcheck, `gosu` lets the entrypoint drop privileges.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates gosu tini \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend

COPY backend/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/ ./
COPY --from=frontend /build/dist /app/frontend/dist
# The node agent ships inside the image: the installer is served verbatim by
# GET /api/v1/nodes/agent/install.sh and the zipapps are published to /downloads
# on boot (see app.main._seed_downloads), so a fresh deployment can provision
# nodes without any manual publish step.
COPY node-agent/ /app/node-agent/
RUN cd /app/node-agent && python3 build.sh >/dev/null && rm -rf build
COPY docker/entrypoint-panel.sh /usr/local/bin/titan-entrypoint
COPY docker/healthcheck.sh /usr/local/bin/titan-healthcheck
RUN chmod +x /usr/local/bin/titan-entrypoint /usr/local/bin/titan-healthcheck \
 && mkdir -p /data/state /data/downloads \
 && useradd --system --uid 10001 --home /app titan \
 && chown -R titan:titan /app /data

ENV TITAN_STATE_DIR=/data/state \
    DATA_DIR=/data \
    HOST=0.0.0.0 \
    PORT=8080 \
    ENV=production \
    PYTHONPATH=/app/backend

EXPOSE 8080
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["/usr/local/bin/titan-healthcheck"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/titan-entrypoint"]
CMD ["serve"]

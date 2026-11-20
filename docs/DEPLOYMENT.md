# Nosia Deployment Guide

**Warning**: This is a **draft** and evolving document. Please contribute improvements via pull requests.

Complete guide for deploying Nosia to production environments with best practices for security, reliability, and scalability.

## Table of Contents

1. [Deployment Options](#deployment-options)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Docker Compose Deployment](#docker-compose-deployment)
4. [Kamal Deployment](#kamal-deployment)
5. [Kubernetes Deployment](#kubernetes-deployment)
6. [Environment Variable Management](#environment-variable-management)
7. [Database Management](#database-management)
8. [Backup Strategies](#backup-strategies)
9. [Monitoring & Logging](#monitoring--logging)
10. [Security Best Practices](#security-best-practices)
11. [Scaling Strategies](#scaling-strategies)
12. [Troubleshooting](#troubleshooting)

---

## Deployment Options

Nosia supports multiple deployment strategies depending on your infrastructure and requirements:

| Deployment Method | Best For | Complexity | Scalability |
|-------------------|----------|------------|-------------|
| **Docker Compose** | Single server, development, small teams | Low | Limited |
| **Kamal** | Multiple servers, simple scaling | Medium | Good |
| **Kubernetes** | Enterprise, high availability | High | Excellent |
| **Manual** | Custom infrastructure | High | Variable |

---

## Pre-Deployment Checklist

Before deploying to production, ensure you have:

### Infrastructure Requirements

- [ ] **Server/VM** with minimum specifications:
  - 2 CPU cores (4+ recommended)
  - 4GB RAM (8GB+ recommended)
  - 20GB storage (50GB+ recommended for documents)
  - Ubuntu 20.04+ or Debian 11+

- [ ] **Database Server** (can be same server for small deployments):
  - PostgreSQL 16+ with pgvector extension
  - 2GB+ RAM allocated
  - SSD storage for better performance

- [ ] **AI Model Service**:
  - Docker Model Runner, Ollama, Infomaniak, OpenAI, or compatible service
  - Separate GPU server recommended for large models
  - Network access from Nosia server

### Security Requirements

- [ ] **SSL/TLS Certificate** (automated with Caddy or Let's Encrypt)
- [ ] **Domain Name** configured with DNS A records
- [ ] **Firewall Rules** configured (ports 80, 443, 5432 if external DB)
- [ ] **SSH Key Authentication** for server access
- [ ] **Strong Passwords** for all services

### Configuration Prepared

- [ ] Environment variables documented
- [ ] Secret key generated (`bin/rails secret`)
- [ ] Database passwords generated
- [ ] API keys obtained (if using external services)
- [ ] MCP server credentials (if using catalog servers)
- [ ] Backup storage configured (S3, local, etc.)

---

## Docker Compose Deployment

The simplest production deployment for single-server setups.

### 1. Server Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose (if not included)
sudo apt install docker-compose-plugin

# Logout and login for group changes to take effect
```

### 2. Clone Repository

```bash
# Create application directory
sudo mkdir -p /opt/nosia
sudo chown $USER:$USER /opt/nosia
cd /opt/nosia

# Clone repository (or upload release)
git clone https://github.com/nosia-ai/nosia.git .
```

### 3. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Generate secure secret key
SECRET_KEY=$(docker run --rm ruby:3.4-slim ruby -e "require 'securerandom'; puts SecureRandom.hex(64)")

# Edit environment file
nano .env
```

**Required Production Configuration**:

```bash
# Application
NOSIA_URL=https://nosia.yourdomain.com
SECRET_KEY_BASE=<generated-secret-key>
RAILS_ENV=production

# Database
DATABASE_URL=postgresql://nosia:secure_password@postgres-db:5432/nosia_production

# AI Services
AI_BASE_URL=http://your-ai-service:11434/v1
AI_API_KEY=your-api-key-if-needed

# Models
LLM_MODEL=granite3.3:2b
EMBEDDING_MODEL=granite-embedding:278m
EMBEDDING_DIMENSIONS=768

# Optimization
LLM_TEMPERATURE=0.1
LLM_MAX_TOKENS=1024
LLM_NUM_CTX=8192
RETRIEVAL_FETCH_K=3
CHUNK_MAX_TOKENS=512
CHUNK_MIN_TOKENS=128
```

### 4. Configure Caddy (Reverse Proxy)

The default Caddyfile serves `nosia.localhost` using Caddy's local CA; follow [Local HTTPS](LOCAL_HTTPS.md) for optional host trust, verification, and removal. Caddy terminates HTTPS and forwards private HTTP directly to Puma at `web:3000`.

The example below is for a **real public domain**, not local setup. Configure its DNS/reachability and `TLS_EMAIL` for automatic public ACME certificates; no local CA import is needed. Do not force `tls internal` for all deployments. Edit `Caddyfile`, replacing the example hostname with your public domain:

```caddyfile
nosia.yourdomain.com {
    # Enable automatic HTTPS
    tls {$TLS_EMAIL:admin@example.com}
    
    # Reverse proxy to Rails
    reverse_proxy web:3000 {
        # Health check
        health_uri /up
        health_interval 10s
        health_timeout 5s
        
        # Connection settings
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
    }
    
    # Security headers
    header {
        # Enable HSTS
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        # Prevent clickjacking
        X-Frame-Options "SAMEORIGIN"
        # Prevent MIME sniffing
        X-Content-Type-Options "nosniff"
        # XSS Protection
        X-XSS-Protection "1; mode=block"
        # Referrer Policy (also safe for MCP OAuth responses)
        Referrer-Policy "no-referrer"
        # Remove server identification
        -Server
    }
    
    # Enable access logs only after configuring the OAuth exclusions below.
}
```

If using MCP OAuth, keep the query string on requests to `/mcp/oauth/callback`
and consent redirect `Location` values out of proxy, access, and tracing logs.
Wherever request or response headers or bodies are captured, including outbound
MCP and provider traffic, also exclude OAuth tokens (including access and
refresh tokens), client secrets, and signing material. Exclude authorization
codes and PKCE code verifiers from outbound OAuth token exchange body logs.
If the logging system cannot reliably redact these values, disable capture of
the affected requests and responses. Preserve `Referrer-Policy: no-referrer` and
`Cache-Control: no-store` on OAuth responses. See the
[MCP workspace deployment requirements](mcp-workspace.md#provider-and-deployment-requirements)
for the exact public origin and existing encryption settings.

### 5. Production Docker Compose

Create `docker-compose.prod.yml`. Supply the existing encryption keys through
your deployment's secret mechanism. Do not put key values in the Compose file.

```yaml
version: '3.8'

services:
  reverse-proxy:
    image: caddy:latest
    restart: always
    ports:
      - "80:80"
      - "443:443"
    environment:
      - NOSIA_URL=${NOSIA_URL}
      - TLS_EMAIL=${TLS_EMAIL}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-config:/config
      - caddy-data:/data
    networks:
      - nosia-network
    depends_on:
      web:
        condition: service_healthy

  web:
    image: dilolabs/nosia:latest
    restart: always
    environment:
      - RAILS_ENV=production
      - DATABASE_URL=${DATABASE_URL}
      - NOSIA_URL=${NOSIA_URL}
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY}
      - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY}
      - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT}
      - AI_BASE_URL=${AI_BASE_URL}
      - AI_API_KEY=${AI_API_KEY}
      - LLM_MODEL=${LLM_MODEL}
      - EMBEDDING_MODEL=${EMBEDDING_MODEL}
      - EMBEDDING_DIMENSIONS=${EMBEDDING_DIMENSIONS}
      - LLM_TEMPERATURE=${LLM_TEMPERATURE}
      - LLM_MAX_TOKENS=${LLM_MAX_TOKENS}
      - LLM_NUM_CTX=${LLM_NUM_CTX}
      - RETRIEVAL_FETCH_K=${RETRIEVAL_FETCH_K}
      - CHUNK_MAX_TOKENS=${CHUNK_MAX_TOKENS}
      - CHUNK_MIN_TOKENS=${CHUNK_MIN_TOKENS}
    volumes:
      - rails-storage:/rails/storage
    networks:
      - nosia-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/up"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    depends_on:
      postgres-db:
        condition: service_healthy
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  solidq:
    image: dilolabs/nosia:latest
    restart: always
    command: bundle exec rake solid_queue:start
    environment:
      - RAILS_ENV=production
      - DATABASE_URL=${DATABASE_URL}
      - NOSIA_URL=${NOSIA_URL}
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY}
      - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY}
      - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT}
      - AI_BASE_URL=${AI_BASE_URL}
      - AI_API_KEY=${AI_API_KEY}
      - LLM_MODEL=${LLM_MODEL}
      - EMBEDDING_MODEL=${EMBEDDING_MODEL}
      - EMBEDDING_DIMENSIONS=${EMBEDDING_DIMENSIONS}
      - LLM_TEMPERATURE=${LLM_TEMPERATURE}
    volumes:
      - rails-storage:/rails/storage
    networks:
      - nosia-network
    depends_on:
      postgres-db:
        condition: service_healthy
      web:
        condition: service_healthy
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  postgres-db:
    image: pgvector/pgvector:pg16
    restart: always
    environment:
      - POSTGRES_DB=${POSTGRES_DB:-nosia_production}
      - POSTGRES_USER=${POSTGRES_USER:-nosia}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_INITDB_ARGS="-E UTF8 --locale=en_US.UTF-8"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./backups:/backups
    networks:
      - nosia-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-nosia}"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    # Optional: Expose for external backups
    # ports:
    #   - "127.0.0.1:5432:5432"

  # Optional: LLM service (if self-hosted)
  # llm:
  #   image: ollama/ollama:latest
  #   restart: always
  #   volumes:
  #     - ollama-models:/root/.ollama
  #   networks:
  #     - nosia-network
  #   deploy:
  #     resources:
  #       reservations:
  #         devices:
  #           - driver: nvidia
  #             count: 1
  #             capabilities: [gpu]

volumes:
  caddy-config:
    driver: local
  caddy-data:
    driver: local
  postgres-data:
    driver: local
  rails-storage:
    driver: local
  # ollama-models:
  #   driver: local

networks:
  nosia-network:
    driver: bridge
```

### 6. Deploy

```bash
# Pull latest images
docker compose -f docker-compose.prod.yml pull

# Start services
docker compose -f docker-compose.prod.yml up -d

# Check logs
docker compose -f docker-compose.prod.yml logs -f

# Verify health
docker compose -f docker-compose.prod.yml ps
```

### 7. Create First Admin User

```bash
# Access Rails console
docker compose -f docker-compose.prod.yml exec web bin/rails console

# In console:
user = User.create!(
  email: 'admin@yourdomain.com',
  name: 'Admin User',
  password: 'secure_password',
  admin: true
)

account = Account.create!(
  name: 'Default Account',
  owner: user
)

exit
```

### 8. Set Up Systemd Service (Optional)

Create `/etc/systemd/system/nosia.service`:

```ini
[Unit]
Description=Nosia Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/nosia
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable nosia
sudo systemctl start nosia
```

---

## Kamal Deployment

Kamal enables zero-downtime deployments across multiple servers with minimal configuration.

### 1. Install Kamal

```bash
# On local machine
gem install kamal
```

### 2. Configure Deployment

The repository includes Kamal configuration. Edit `config/deploy.yml`:

```yaml
service: nosia
image: your-registry.com/nosia

servers:
  web:
    - 192.168.1.10
    - 192.168.1.11
  workers:
    hosts:
      - 192.168.1.12
    cmd: bundle exec rake solid_queue:start

proxy:
  ssl: true
  host: nosia.yourdomain.com

registry:
  server: registry.yourdomain.com
  username: deploy
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    RAILS_ENV: production
    EMBEDDING_DIMENSIONS: 768
  secret:
    - SECRET_KEY_BASE
    - DATABASE_URL
    - AI_BASE_URL
    - AI_API_KEY
    - LLM_MODEL
    - EMBEDDING_MODEL

accessories:
  db:
    image: pgvector/pgvector:pg16
    host: 192.168.1.20
    port: 5432
    env:
      secret:
        - POSTGRES_PASSWORD
      clear:
        POSTGRES_DB: nosia_production
        POSTGRES_USER: nosia
    directories:
      - data:/var/lib/postgresql/data

volumes:
  - rails_storage:/rails/storage

healthcheck:
  path: /up
  interval: 30s

boot:
  limit: "25%"
  wait: 5
```

### 3. Set Up Secrets

Create `.kamal/secrets`:

```bash
# Registry credentials
KAMAL_REGISTRY_PASSWORD=<your-registry-password>

# Application secrets
SECRET_KEY_BASE=<generated-secret-key>
DATABASE_URL=postgresql://nosia:password@db:5432/nosia_production

# AI configuration
AI_BASE_URL=http://your-ai-service:11434/v1
AI_API_KEY=<your-api-key>
LLM_MODEL=granite3.3:2b
EMBEDDING_MODEL=granite-embedding:278m

# Database
POSTGRES_PASSWORD=<secure-db-password>
```

### 4. Initial Setup

```bash
# Set up servers (install Docker, create directories)
kamal setup

# Deploy application
kamal deploy
```

### 5. Ongoing Deployments

```bash
# Deploy updates (zero-downtime)
kamal deploy

# Rollback if needed
kamal rollback

# View logs
kamal logs -f

# Access console
kamal app exec --interactive "bin/rails console"

# Run database migrations
kamal app exec "bin/rails db:migrate"
```

---

## Kubernetes Deployment

For enterprise deployments requiring high availability and auto-scaling.

### 1. Create Namespace

```yaml
# kubernetes/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nosia
```

### 2. Configuration Management

**ConfigMap** (`kubernetes/configmap.yaml`):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nosia-config
  namespace: nosia
data:
  RAILS_ENV: "production"
  EMBEDDING_DIMENSIONS: "768"
  LLM_TEMPERATURE: "0.1"
  LLM_MAX_TOKENS: "1024"
  LLM_NUM_CTX: "8192"
  RETRIEVAL_FETCH_K: "3"
  CHUNK_MAX_TOKENS: "512"
  CHUNK_MIN_TOKENS: "128"
```

**Secrets** (`kubernetes/secrets.yaml`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: nosia-secrets
  namespace: nosia
type: Opaque
stringData:
  SECRET_KEY_BASE: "<base64-encoded-secret>"
  DATABASE_URL: "postgresql://user:pass@postgres:5432/nosia"
  AI_BASE_URL: "http://ai-service:11434/v1"
  AI_API_KEY: "<your-api-key>"
  LLM_MODEL: "granite3.3:2b"
  EMBEDDING_MODEL: "granite-embedding:278m"
```

### 3. Database (StatefulSet)

```yaml
# kubernetes/postgres-statefulset.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: nosia
spec:
  ports:
    - port: 5432
  clusterIP: None
  selector:
    app: postgres
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: nosia
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: pgvector/pgvector:pg16
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: nosia_production
            - name: POSTGRES_USER
              value: nosia
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: nosia-secrets
                  key: POSTGRES_PASSWORD
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              memory: "2Gi"
              cpu: "500m"
            limits:
              memory: "4Gi"
              cpu: "2000m"
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 50Gi
```

### 4. Web Application (Deployment)

```yaml
# kubernetes/web-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nosia-web
  namespace: nosia
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nosia-web
  template:
    metadata:
      labels:
        app: nosia-web
    spec:
      containers:
        - name: web
          image: dilolabs/nosia:latest
          ports:
            - containerPort: 3000
          envFrom:
            - configMapRef:
                name: nosia-config
            - secretRef:
                name: nosia-secrets
          livenessProbe:
            httpGet:
              path: /up
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /up
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "2Gi"
              cpu: "1000m"
          volumeMounts:
            - name: storage
              mountPath: /rails/storage
      volumes:
        - name: storage
          persistentVolumeClaim:
            claimName: rails-storage
---
apiVersion: v1
kind: Service
metadata:
  name: nosia-web
  namespace: nosia
spec:
  selector:
    app: nosia-web
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
  type: ClusterIP
```

### 5. Worker (Deployment)

```yaml
# kubernetes/worker-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nosia-worker
  namespace: nosia
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nosia-worker
  template:
    metadata:
      labels:
        app: nosia-worker
    spec:
      containers:
        - name: worker
          image: dilolabs/nosia:latest
          command: ["bundle", "exec", "rake", "solid_queue:start"]
          envFrom:
            - configMapRef:
                name: nosia-config
            - secretRef:
                name: nosia-secrets
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "2Gi"
              cpu: "1000m"
          volumeMounts:
            - name: storage
              mountPath: /rails/storage
      volumes:
        - name: storage
          persistentVolumeClaim:
            claimName: rails-storage
```

### 6. Ingress (LoadBalancer)

```yaml
# kubernetes/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nosia-ingress
  namespace: nosia
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - nosia.yourdomain.com
      secretName: nosia-tls
  rules:
    - host: nosia.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nosia-web
                port:
                  number: 80
```

### 7. Persistent Storage

```yaml
# kubernetes/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rails-storage
  namespace: nosia
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: nfs-client # or your storage class
```

### 8. Deploy to Kubernetes

```bash
# Apply all configurations
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/configmap.yaml
kubectl apply -f kubernetes/secrets.yaml
kubectl apply -f kubernetes/postgres-statefulset.yaml
kubectl apply -f kubernetes/pvc.yaml
kubectl apply -f kubernetes/web-deployment.yaml
kubectl apply -f kubernetes/worker-deployment.yaml
kubectl apply -f kubernetes/ingress.yaml

# Check status
kubectl get pods -n nosia
kubectl get services -n nosia

# View logs
kubectl logs -n nosia -l app=nosia-web -f

# Access console
kubectl exec -it -n nosia deployment/nosia-web -- bin/rails console
```

---

## RubyLLM 2.2 and MCP OAuth upgrade

This is a maintenance upgrade, not a rolling restart. Rehearse with a
representative database copy before scheduling it. If you are still on 1.x,
first follow the separate [RubyLLM 2.0 operator runbook](upgrades/ruby-llm-2-deployment.md).

1. Back up the deployment database and preserve matching application images,
   attachment storage, configuration, and the existing Rails encryption keys.
   Rehearse [restoring to a new database](#restore-a-custom-archive) and testing
   it with the old image. Include any separate databases needed for recovery.
2. Block new work, drain in-flight requests and jobs, and stop web and worker
   processes (including schedules and retries) that touch RubyLLM rows. If
   writes occurred since the backup, capture a consistent recovery point now.
   Keep those writers stopped through migration and verification.
3. Use the [one-off migration commands](#run-migrations-without-starting-services)
   from the final image. The checked-in versions run in order:
   `20261119000001` (RubyLLM 2.1), `20261119000002` (2.2),
   `20261119000003` and `20261119000004` (OAuth and user binding), then
   `20261120000001` (MCP connection revisions). Do not run generated migrations
   or load `db/schema.rb` on the existing database.
4. Confirm the migration versions and database connectivity. Check existing chats,
   messages, tool results, usage history, MCP configuration and chat links against
   the pre-upgrade data. Confirm the final image can decrypt existing MCP settings
   with the deployment’s current keys without logging their contents. Use the
   [web-only smoke check](#smoke-test-the-web-image-without-workers) to verify
   `/up` and authenticated access. Only after these checks pass, start the final
   services and resume traffic and workers.

If a check fails, keep writers stopped and diagnose before resuming. If rollback
requires the old schema, restore the verified backup into a **new recovery
database** using the [custom archive procedure](#restore-a-custom-archive). Boot
the matching old image with private settings pointing to the restored database,
the existing encryption keys, and matching restored storage. Verify the old
image with the web-only smoke check, including authenticated access and restored
data, before switching traffic or starting workers. Configure normal web and
worker launches to use the verified recovery database and old image; do not
restart containers that still target the upgraded database or run the final
image’s Compose `db-migrate` service against the recovery database. Do not run
generated `down` migrations, `db:rollback`, or old writers against the new
schema. The recovery database does not include writes after the chosen
recovery point; account for those before switching.

See the [local verification results](reports/mcp-oauth-verification.md). They
do not approve a production rollout.

### Run migrations without starting services

Run these Docker commands from a maintenance host. Set `FINAL_IMAGE` to the
reviewed final image by digest, `MAINTENANCE_NETWORK` to a restricted Docker
network that can reach the reviewed database, and `TARGET_DB` to its exact
database name. Set `FINAL_ENV_FILE` to a private, permission-restricted
`docker run --env-file` file containing the reviewed `DATABASE_URL`, Rails
secrets (including the existing encryption keys), and other required settings.
Verify the server and role in that configuration and any separate database
targets; the script checks the connected primary database name but does not
identify the server. Do not print or copy the env file into logs.

```bash
run_migration_task() {
  docker run --rm --network "${MAINTENANCE_NETWORK:?}" \
    --env-file "${FINAL_ENV_FILE:?}" -e RAILS_ENV=production -e "EXPECTED_DB=${TARGET_DB:?}" \
    --entrypoint /bin/sh "${FINAL_IMAGE:?}" -eu -c '
      bin/rails runner "
        db = ApplicationRecord.connection.select_value(%q[SELECT current_database()])
        abort %q[Unexpected primary database] unless db == ENV.fetch(%q[EXPECTED_DB])
        puts db
      "
      exec bin/rails "$1"
    ' sh "$1"
}
run_migration_task db:migrate:status
```

Review every pending migration. While affected writers remain stopped, run:

```bash
run_migration_task db:migrate && run_migration_task db:migrate:status
```

The entrypoint override invokes only the requested Rails tasks. It does not
run `bin/boot`, `bin/start-app` (which runs `db:prepare`), the Compose
`db-migrate` service, or Solid Queue.

### Smoke-test the web image without workers

Use the reviewed maintenance network and a matching local storage copy. For
object storage, use an isolated bucket in the private env file and omit the
storage bind mount below. Verify the settings before boot. Run only one smoke
container at a time; its port is published to host loopback, not to the public
proxy.

```bash
smoke_web() {
  docker run --rm --name nosia-mcp-smoke --network "${MAINTENANCE_NETWORK:?}" \
    --env-file "${2:?}" -e RAILS_ENV=production -e "EXPECTED_DB=${3:?}" -e PORT=3000 \
    --mount "type=bind,source=${4:?},target=/rails/storage,readonly" \
    -p 127.0.0.1:13000:3000 --entrypoint /bin/sh "${1:?}" -eu -c '
      bin/rails runner "
        db = ApplicationRecord.connection.select_value(%q[SELECT current_database()])
        abort %q[Unexpected primary database] unless db == ENV.fetch(%q[EXPECTED_DB])
        puts db
      "
      exec bin/rails server -b 0.0.0.0 -p 3000
    '
}
```

For the upgraded image, set `SMOKE_STORAGE_DIR` to the absolute path of the
matching storage copy and run:

```bash
smoke_web "$FINAL_IMAGE" "$FINAL_ENV_FILE" "$TARGET_DB" "$SMOKE_STORAGE_DIR"
```

For recovery or a restore rehearsal, use the matching `OLD_IMAGE` pinned by
digest. Set `RECOVERY_ENV_FILE` to the private settings for the restored
database and existing keys, and `RECOVERY_STORAGE_DIR` to the absolute path
of the matching restored storage. Run this instead:

```bash
smoke_web "$OLD_IMAGE" "$RECOVERY_ENV_FILE" "$RECOVERY_DB" "$RECOVERY_STORAGE_DIR"
```

In a second terminal, once Puma is listening:

```bash
status=$(docker exec nosia-mcp-smoke curl --fail --silent --show-error \
  --output /dev/null --write-out '%{http_code}' http://127.0.0.1:3000/up)
test "$status" = 200
```

Confirm an HTTP 200 and check authenticated read-only access through a private
HTTPS endpoint or tunnel; do not test against live providers during the
rehearsal. Stop the foreground smoke container before starting normal services.
This boots Rails/Puma only; it does not migrate or start queue workers.

---

## Environment Variable Management

### Production Environment Variables

**Critical Security Variables**:
```bash
SECRET_KEY_BASE=<64-char-hex>      # Generate: bin/rails secret
DATABASE_URL=postgresql://...      # Full connection string
AI_API_KEY=<api-key>              # If using external AI service
```

**AI Configuration**:
```bash
AI_BASE_URL=http://ai-service:11434/v1
LLM_MODEL=granite3.3:2b
EMBEDDING_MODEL=granite-embedding:278m
EMBEDDING_DIMENSIONS=768
```

**MCP Configuration** (Optional):

Configure individual servers in the web workspace. OAuth uses public HTTPS
Streamable HTTP, the exact public `NOSIA_URL` origin, and the existing Rails
encryption keys. See [MCP workspace](mcp-workspace.md#connect-with-oauth).

**Performance Tuning**:
```bash
LLM_TEMPERATURE=0.1               # 0.0-1.0, lower = more deterministic
LLM_MAX_TOKENS=1024              # Max response length
LLM_NUM_CTX=8192                 # Context window size
LLM_TOP_K=40                     # Sampling parameter
LLM_TOP_P=0.9                    # Nucleus sampling
RETRIEVAL_FETCH_K=3              # Chunks to retrieve
CHUNK_MAX_TOKENS=512             # Maximum chunk size
CHUNK_MIN_TOKENS=128             # Minimum chunk size
CHUNK_MERGE_PEERS=true           # Merge small chunks
```

**Application Settings**:
```bash
RAILS_ENV=production
RAILS_LOG_LEVEL=info             # debug, info, warn, error
RAILS_MAX_THREADS=5              # Puma threads
WEB_CONCURRENCY=2                # Puma workers
```

### Secrets Management Best Practices

**1. Never Commit Secrets**:
```bash
# .gitignore
.env
.env.*
!.env.example
.kamal/secrets
kubernetes/secrets.yaml
```

**2. Use Secret Management Tools**:

**Vault (HashiCorp)**:
```bash
# Store secrets in Vault
vault kv put secret/nosia/production \
  SECRET_KEY_BASE="..." \
  DATABASE_URL="..." \
  AI_API_KEY="..."

# Retrieve in deployment
export SECRET_KEY_BASE=$(vault kv get -field=SECRET_KEY_BASE secret/nosia/production)
```

**AWS Secrets Manager**:
```bash
# Store secret
aws secretsmanager create-secret \
  --name nosia/production/secrets \
  --secret-string file://secrets.json

# Retrieve in deployment
aws secretsmanager get-secret-value \
  --secret-id nosia/production/secrets \
  --query SecretString
```

**Docker Secrets** (Swarm):
```bash
# Create secret
echo "my-secret-key" | docker secret create secret_key_base -

# Use in docker-compose.yml
services:
  web:
    secrets:
      - secret_key_base
secrets:
  secret_key_base:
    external: true
```

**Kubernetes Secrets**:
```bash
# Create from file
kubectl create secret generic nosia-secrets \
  --from-env-file=.env.production \
  --namespace=nosia

# Create from literals
kubectl create secret generic nosia-secrets \
  --from-literal=SECRET_KEY_BASE='...' \
  --from-literal=DATABASE_URL='...' \
  --namespace=nosia
```

**3. Environment-Specific Configuration**:

```
.env.production       # Production secrets (never commit)
.env.staging          # Staging secrets (never commit)
.env.example          # Template (commit this)
```

**4. Rotation Strategy**:

```bash
# Schedule regular rotation
# 1. Generate new secret
NEW_SECRET=$(openssl rand -hex 64)

# 2. Update secret manager
# 3. Deploy with new secret
# 4. Verify functionality
# 5. Remove old secret
```

---

## Database Management

### Initial Setup

```bash
# Create database and run migrations
docker compose exec web bin/rails db:create db:migrate

# Or with Kamal
kamal app exec "bin/rails db:create db:migrate"

# Or with Kubernetes
kubectl exec -n nosia deployment/nosia-web -- bin/rails db:create db:migrate
```

### Database Migrations

**Before Deploying New Version**:

```bash
# Review pending migrations
docker compose exec web bin/rails db:migrate:status

# Run migrations
docker compose exec web bin/rails db:migrate

# Rollback if needed
docker compose exec web bin/rails db:rollback STEP=1
```

**Zero-Downtime Migrations**:

1. Make migrations backward compatible
2. Deploy code that works with old and new schema
3. Run migrations
4. Deploy code that only uses new schema

### Database Maintenance

**Vacuum and Analyze**:

```bash
# Enter PostgreSQL container
docker compose exec postgres-db psql -U nosia -d nosia_production

# Run vacuum
VACUUM ANALYZE;

# Check database size
SELECT pg_size_pretty(pg_database_size('nosia_production'));

# Check table sizes
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
```

**Optimize Vector Indexes**:

```sql
-- Rebuild vector index if performance degrades
REINDEX INDEX index_chunks_on_embedding;

-- Update statistics
ANALYZE chunks;
```

**Connection Pooling**:

For high-traffic deployments, use PgBouncer:

```yaml
# docker-compose.prod.yml
services:
  pgbouncer:
    image: pgbouncer/pgbouncer:latest
    environment:
      - DATABASES_HOST=postgres-db
      - DATABASES_PORT=5432
      - DATABASES_USER=nosia
      - DATABASES_PASSWORD=${POSTGRES_PASSWORD}
      - DATABASES_DBNAME=nosia_production
      - POOL_MODE=transaction
      - MAX_CLIENT_CONN=1000
      - DEFAULT_POOL_SIZE=25
    ports:
      - "6432:6432"
    depends_on:
      - postgres-db

  web:
    environment:
      # Point to PgBouncer instead of direct database
      - DATABASE_URL=postgresql://nosia:password@pgbouncer:6432/nosia_production
```

---

## Backup Strategies

### Database Backups

**1. Automated Daily Backups**:

Create backup script (`/opt/nosia/scripts/backup-db.sh`):

```bash
#!/bin/bash
set -euo pipefail
umask 077

# Configuration
BACKUP_DIR="/opt/nosia/backups"
DB_CONTAINER="postgres-db"
DB_NAME="nosia_production"
DB_USER="nosia"
RETENTION_DAYS=30

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Generate filename with timestamp
BACKUP_FILE="$BACKUP_DIR/nosia-db-$(date +%Y%m%d-%H%M%S).sql.gz"

# Perform backup
docker compose exec -T "$DB_CONTAINER" pg_dump \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  --format=custom \
  --compress=9 \
  | gzip > "$BACKUP_FILE.partial"
gzip -t -- "$BACKUP_FILE.partial"
mv -- "$BACKUP_FILE.partial" "$BACKUP_FILE"

# Verify backup
if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
  echo "Backup successful: $BACKUP_FILE"
  
  # Calculate size
  SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "Backup size: $SIZE"
else
  echo "Backup failed!"
  exit 1
fi

# Remove old backups
find "$BACKUP_DIR" -name "nosia-db-*.sql.gz" -mtime +$RETENTION_DAYS -delete
echo "Old backups cleaned (retention: $RETENTION_DAYS days)"

# Optional: Upload to S3
# aws s3 cp "$BACKUP_FILE" "s3://your-bucket/nosia-backups/"

# Optional: Send notification
# curl -X POST https://hooks.slack.com/... -d "{'text':'Nosia backup completed: $SIZE'}"
```

Make executable and schedule:

```bash
chmod +x /opt/nosia/scripts/backup-db.sh

# Add to crontab
crontab -e

# Daily at 2 AM
0 2 * * * /opt/nosia/scripts/backup-db.sh >> /var/log/nosia-backup.log 2>&1
```

**2. Point-in-Time Recovery (PITR)**:

Enable WAL archiving in PostgreSQL:

```yaml
# docker-compose.prod.yml
services:
  postgres-db:
    command: >
      postgres
      -c wal_level=replica
      -c archive_mode=on
      -c archive_command='test ! -f /backups/wal/%f && cp %p /backups/wal/%f'
      -c max_wal_senders=3
      -c wal_keep_size=1GB
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./backups/wal:/backups/wal
```

### Restore a custom archive

The daily backup’s `.sql.gz` suffix is historical: its contents are a
gzip-wrapped **custom** `pg_dump` archive, not SQL. Unwrap it with `gzip`
and use `pg_restore`, not `psql`.

Use a reviewed Compose file and project with a running `postgres-db` service on
the intended PostgreSQL cluster. For a rehearsal, use an isolated cluster and
storage copy. Keep writers and public ingress stopped for production recovery.
Provision the PostgreSQL roles from the backup and ensure required extensions
such as pgvector are available. Use a restore role with permission to create
the database and restore the archived ownership and grants. Match the source
encoding, locale, and database-level settings; review any `createdb` flags
needed for those settings. Supply credentials through the deployment's secret
mechanism. Do not use the source database as the restore target.

Set `RESTORE_COMPOSE_FILE`, `RESTORE_PROJECT`, `DB_USER` (the restore role),
`DB_OWNER` (the source database’s owner), `SOURCE_DB`, and the absolute
`BACKUP_FILE` (the verified archive for the recovery point). Choose a new
`RECOVERY_DB` such as `nosia_recovery_20261120_1030` for recovery or
`nosia_rehearsal_20261120_1030` for a rehearsal.

```bash
#!/bin/bash
set -euo pipefail
: "${RESTORE_COMPOSE_FILE:?}" "${RESTORE_PROJECT:?}" "${DB_USER:?}" "${DB_OWNER:?}" \
  "${SOURCE_DB:?}" "${RECOVERY_DB:?}" "${BACKUP_FILE:?}"
if [[ ! "$RECOVERY_DB" =~ ^nosia_(recovery|rehearsal)_[a-z0-9_]+$ ||
      ${#RECOVERY_DB} -gt 63 || "$RECOVERY_DB" == "$SOURCE_DB" ]]; then
  echo "Choose a new nosia_recovery_* or nosia_rehearsal_* database." >&2
  exit 1
fi

compose=(docker compose -f "$RESTORE_COMPOSE_FILE" -p "$RESTORE_PROJECT")
pg() { "${compose[@]}" exec -T postgres-db "$@"; }
sql() { pg psql -X -w -v ON_ERROR_STOP=1 -U "$DB_USER" "$@"; }

gzip -t -- "$BACKUP_FILE"
container_id=$("${compose[@]}" ps -q postgres-db)
test -n "$container_id"
printf 'PostgreSQL service container: %s\n' "$container_id"
sql -d postgres -c 'SELECT current_database(), current_user, version();'
read -r -p "After checking the cluster and archive, enter the new database name: " confirmed
test "$confirmed" = "$RECOVERY_DB"

# A pre-existing name is an error. Do not clean, drop, or reuse it.
pg createdb -w -U "$DB_USER" --maintenance-db=postgres --template=template0 \
  --owner="$DB_OWNER" "$RECOVERY_DB"
test "$(sql -d "$RECOVERY_DB" -Atc 'SELECT current_database();')" = "$RECOVERY_DB"
gzip -dc -- "$BACKUP_FILE" | pg pg_restore -w -U "$DB_USER" \
  --dbname="$RECOVERY_DB" --exit-on-error --single-transaction
sql -d "$RECOVERY_DB" -c 'SELECT current_database(), count(*) FROM accounts;'
```

If any command fails, stop and investigate; do not point the application at
that database. After a successful restore, compare the expected records with
the backup’s recovery point, check matching attachments, and smoke-test the
matching image and encryption settings before routing traffic or starting
workers. Keep the original database intact.

### File Storage Backups

**1. Rails Storage (Uploaded Documents)**:

```bash
# Backup storage volume
docker run --rm \
  -v nosia_rails-storage:/source:ro \
  -v /opt/nosia/backups:/backup \
  alpine tar czf /backup/rails-storage-$(date +%Y%m%d).tar.gz -C /source .

# Restore storage
docker run --rm \
  -v nosia_rails-storage:/target \
  -v /opt/nosia/backups:/backup \
  alpine tar xzf /backup/rails-storage-20240101.tar.gz -C /target
```

**2. S3 Storage (Recommended for Production)**:

Configure Active Storage to use S3:

```ruby
# config/storage.yml
production:
  service: S3
  access_key_id: <%= ENV['AWS_ACCESS_KEY_ID'] %>
  secret_access_key: <%= ENV['AWS_SECRET_ACCESS_KEY'] %>
  region: <%= ENV['AWS_REGION'] %>
  bucket: <%= ENV['AWS_S3_BUCKET'] %>
```

```ruby
# config/environments/production.rb
config.active_storage.service = :production
```

Enable versioning and lifecycle policies on S3 bucket.

### Backup Testing

Regularly follow the [custom archive procedure](#restore-a-custom-archive) with
a fresh `nosia_rehearsal_*` database in an isolated environment. Verify data
and attachments with the [web-only smoke check](#smoke-test-the-web-image-without-workers)
using the image that matches the backup. The rehearsal does not switch traffic
or drop the source or restored database.

### Disaster Recovery Plan

**1. Document Recovery Procedures**:

Create `DISASTER_RECOVERY.md` with:
- Contact information for team members
- Access credentials locations
- Step-by-step recovery process
- RTO (Recovery Time Objective) and RPO (Recovery Point Objective)

**2. Off-Site Backups**:

```bash
# Sync to remote server
rsync -avz --delete \
  /opt/nosia/backups/ \
  backup-server:/backups/nosia/

# Or upload to cloud storage
rclone sync /opt/nosia/backups/ remote:nosia-backups/
```

**3. Configuration Backups**:

```bash
# Backup all configuration files
tar czf /opt/nosia/backups/config-$(date +%Y%m%d).tar.gz \
  .env \
  docker-compose.prod.yml \
  Caddyfile \
  config/deploy.yml \
  .kamal/
```

---

## Monitoring & Logging

### Application Monitoring

**1. Health Checks**:

Monitor the `/up` endpoint:

```bash
# Create monitoring script
cat > /opt/nosia/scripts/health-check.sh << 'EOF'
#!/bin/bash
URL="https://nosia.yourdomain.com/up"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$URL")

if [ "$RESPONSE" != "200" ]; then
  echo "Health check failed! Status: $RESPONSE"
  # Send alert
  curl -X POST https://hooks.slack.com/... \
    -d "{\"text\":\"Nosia health check failed: $RESPONSE\"}"
  exit 1
fi
EOF

# Add to cron (every 5 minutes)
*/5 * * * * /opt/nosia/scripts/health-check.sh
```

**2. Application Logs**:

```bash
# View logs
docker compose logs -f web

# Search logs
docker compose logs web | grep ERROR

# Export logs
docker compose logs --since 24h web > /var/log/nosia-web.log
```

**3. Centralized Logging**:

Use log aggregation service (ELK, Loki, or cloud service):

```yaml
# docker-compose.prod.yml
services:
  web:
    logging:
      driver: "fluentd"
      options:
        fluentd-address: localhost:24224
        tag: nosia.web
```

### Database Monitoring

```sql
-- Active connections
SELECT count(*) FROM pg_stat_activity;

-- Long-running queries
SELECT
  pid,
  now() - pg_stat_activity.query_start AS duration,
  query
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';

-- Database size growth
SELECT
  pg_size_pretty(pg_database_size('nosia_production')) as size;

-- Cache hit ratio (should be > 99%)
SELECT
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit) as heap_hit,
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;
```

### Performance Monitoring

**1. Resource Usage**:

```bash
# Monitor container resources
docker stats

# System resources
htop
iotop
```

**2. APM Integration** (Optional):

Add New Relic, Datadog, or Scout APM:

```ruby
# Gemfile
gem 'newrelic_rpm'
gem 'scout_apm'

# config/newrelic.yml
# Configure with license key
```

**3. Custom Metrics**:

```ruby
# config/initializers/metrics.rb
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe('chat.completion') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    # Log metrics
    Rails.logger.info "Chat completion: #{event.duration}ms"
  end
end
```

---

## Security Best Practices

### 1. Network Security

**Firewall Configuration**:

```bash
# UFW (Ubuntu)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw enable

# Or iptables
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -j DROP
```

**Restrict Database Access**:

```yaml
# Only allow internal network
postgres-db:
  networks:
    - nosia-internal

networks:
  nosia-internal:
    internal: true
```

### 2. SSL/TLS Configuration

Ensure strong cipher suites in Caddy:

```caddyfile
{$NOSIA_URL} {
  tls {
    protocols tls1.2 tls1.3
    ciphers TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
  }
}
```

### 3. Application Security

**Set Security Headers** (already in Caddyfile example above).

**Rate Limiting**:

```ruby
# Gemfile
gem 'rack-attack'

# config/initializers/rack_attack.rb
Rack::Attack.throttle('api/ip', limit: 100, period: 1.minute) do |req|
  req.ip if req.path.start_with?('/api/')
end
```

**Database Encryption**:

```bash
# Enable pgcrypto for column-level encryption
docker compose exec postgres-db psql -U nosia -d nosia_production -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
```

### 4. Regular Updates

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Docker images
docker compose pull
docker compose up -d

# Check for vulnerabilities
docker scan dilolabs/nosia:latest
```

### 5. Security Scanning

```bash
# Scan Ruby dependencies
bundle audit check --update

# Scan for security vulnerabilities
bin/brakeman --no-pager

# Scan Docker images
trivy image dilolabs/nosia:latest
```

---

## Scaling Strategies

### Vertical Scaling

Increase resources for existing containers:

```yaml
services:
  web:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G
```

### Horizontal Scaling

**1. Multiple Web Instances**:

```yaml
services:
  web:
    deploy:
      replicas: 3
```

Or with Kubernetes:

```yaml
spec:
  replicas: 5
```

**2. Load Balancing**:

Use Caddy, Nginx, or cloud load balancer to distribute traffic.

**3. Database Scaling**:

- **Read Replicas**: For read-heavy workloads
- **Connection Pooling**: PgBouncer (shown earlier)
- **Partitioning**: Partition large tables by account_id

```sql
-- Partition chunks table
CREATE TABLE chunks_partitioned (
  LIKE chunks INCLUDING ALL
) PARTITION BY HASH (account_id);

-- Create partitions
CREATE TABLE chunks_p0 PARTITION OF chunks_partitioned
  FOR VALUES WITH (MODULUS 4, REMAINDER 0);
```

**4. Cache Layer**:

Add Redis for caching:

```yaml
services:
  redis:
    image: redis:7-alpine
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes
```

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'],
  expires_in: 1.hour
}
```

**5. CDN for Assets**:

Use CloudFlare, CloudFront, or similar CDN for static assets.

---

## Troubleshooting

### Common Issues

**1. Application Won't Start**:

```bash
# Check logs
docker compose logs web

# Common causes:
# - Missing environment variables (check validation)
# - Database connection issues
# - Port conflicts

# Verify environment
docker compose exec web env | grep -E '(DATABASE|SECRET|AI_)'

# Test database connection
docker compose exec web bin/rails db:migrate:status
```

**2. Out of Memory**:

```bash
# Check memory usage
docker stats

# Increase limits in docker-compose.yml
services:
  web:
    mem_limit: 2g
    memswap_limit: 2g

# Or add swap
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

**3. Slow Queries**:

```sql
-- Enable query logging
ALTER DATABASE nosia_production SET log_min_duration_statement = 1000;

-- Check slow queries
SELECT * FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

**4. Database Connection Exhaustion**:

```bash
# Check current connections
docker compose exec postgres-db psql -U nosia -c "SELECT count(*) FROM pg_stat_activity;"

# Increase connection pool
# In .env:
RAILS_MAX_THREADS=10

# In PostgreSQL:
docker compose exec postgres-db psql -U nosia -c "ALTER SYSTEM SET max_connections = 200;"
docker compose restart postgres-db
```

**5. Embedding Generation Failures**:

```bash
# Check AI service connectivity
docker compose exec web curl -v http://ai-service:11434/v1/models

# Check logs for errors
docker compose logs web | grep -i embedding

# Manually trigger regeneration
docker compose exec web bin/rails runner "
  Chunk.where(embedding: nil).find_each do |chunk|
    chunk.generate_embedding!
  end
"
```

### Debug Mode

```bash
# Enable debug logging temporarily
docker compose exec web bin/rails runner "
  Rails.logger.level = Logger::DEBUG
"

# Or set in environment
RAILS_LOG_LEVEL=debug docker compose up web
```

### Support and Community

- **GitHub Issues**: https://github.com/nosia-ai/nosia/issues
- **Documentation**: https://guides.nosia.ai
- **Discussions**: https://github.com/nosia-ai/nosia/discussions

---

## Production Checklist

Before going live, verify:

### Infrastructure
- [ ] SSL/TLS certificates configured and auto-renewing
- [ ] DNS records properly configured
- [ ] Firewall rules in place
- [ ] Backups configured and tested
- [ ] Monitoring and alerting active
- [ ] Log aggregation configured
- [ ] Disaster recovery plan documented

### Security
- [ ] All secrets properly managed (not in code)
- [ ] Strong passwords generated
- [ ] API tokens secured
- [ ] Security headers configured
- [ ] Rate limiting enabled
- [ ] Regular update schedule established

### Performance
- [ ] Database properly tuned
- [ ] Connection pooling configured
- [ ] Caching strategy implemented
- [ ] CDN configured for assets
- [ ] Resource limits set appropriately

### Operations
- [ ] Deployment process documented
- [ ] Rollback procedure tested
- [ ] Health checks configured
- [ ] On-call rotation established
- [ ] Runbooks created for common issues

---

## Conclusion

This guide covers production deployment of Nosia across different infrastructure types. Choose the deployment method that best fits your requirements and follow the security and operational best practices outlined here.

For specific questions or issues, consult the main [ARCHITECTURE.md](ARCHITECTURE.md) documentation or open an issue on GitHub.

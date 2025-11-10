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

Edit `Caddyfile`:

```caddyfile
{$NOSIA_URL:nosia.localhost} {
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
        # Referrer Policy
        Referrer-Policy "strict-origin-when-cross-origin"
        # Remove server identification
        -Server
    }
    
    # Logging
    log {
        output file /data/access.log {
            roll_size 100mb
            roll_keep 5
        }
    }
}
```

### 5. Production Docker Compose

Create `docker-compose.prod.yml`:

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
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
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
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
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
set -e

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
  | gzip > "$BACKUP_FILE"

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

**3. Restore from Backup**:

```bash
# Stop application
docker compose stop web solidq

# Restore database
gunzip -c /opt/nosia/backups/nosia-db-20240101-020000.sql.gz | \
  docker compose exec -T postgres-db psql -U nosia -d nosia_production

# Restart application
docker compose start web solidq
```

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

**Regularly test restoration**:

```bash
#!/bin/bash
# test-restore.sh

# Create test database
docker compose exec postgres-db psql -U nosia -c "CREATE DATABASE nosia_test_restore;"

# Restore to test database
gunzip -c /opt/nosia/backups/latest-backup.sql.gz | \
  docker compose exec -T postgres-db psql -U nosia -d nosia_test_restore

# Verify data
docker compose exec postgres-db psql -U nosia -d nosia_test_restore -c "SELECT COUNT(*) FROM accounts;"

# Cleanup
docker compose exec postgres-db psql -U nosia -c "DROP DATABASE nosia_test_restore;"
```

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

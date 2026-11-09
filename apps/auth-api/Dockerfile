# syntax=docker/dockerfile:1

ARG NODE_VERSION=22-alpine

# ------------------------------------------------------------------
# Install dependencies (including devDependencies)
# ------------------------------------------------------------------
FROM node:${NODE_VERSION} AS deps

WORKDIR /app

RUN apk add --no-cache python3 make g++

COPY package*.json ./

RUN npm ci --no-audit --no-fund

# ------------------------------------------------------------------
# Build application
# ------------------------------------------------------------------
FROM deps AS build

WORKDIR /app

COPY . .

RUN npm run build

# ------------------------------------------------------------------
# Remove dev dependencies
# ------------------------------------------------------------------
FROM deps AS prod-deps

WORKDIR /app

RUN npm prune --omit=dev

# ------------------------------------------------------------------
# Production image
# ------------------------------------------------------------------
FROM node:${NODE_VERSION} AS production

WORKDIR /app

LABEL org.opencontainers.image.title="auth" \
  org.opencontainers.image.description="Auth microservice (NestJS + TypeORM)" \
  org.opencontainers.image.source="https://github.com/virak0001/aws-auth"

ENV NODE_ENV=production \
  HOST=0.0.0.0 \
  PORT=3000

RUN apk add --no-cache tini

COPY --chown=node:node package*.json ./
COPY --from=prod-deps --chown=node:node /app/node_modules ./node_modules
COPY --from=build     --chown=node:node /app/dist ./dist

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/sbin/tini","--"]
CMD ["node","dist/main"]
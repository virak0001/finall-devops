# ── Stage 1: build ──────────────────────────────────────────────────────────
FROM node:22-alpine AS builder
WORKDIR /app

# @bomb.sh/tab (cac, citty, commander) that @nuxt/cli pulls in. The npm 10.9.8
# bundled with node:22 expects them hoisted and fails `npm ci` with "lock file's
# cac@7.0.0 does not satisfy cac@6.7.14". Pinning npm keeps dev and CI resolving
# the same tree — bump it in step with whatever writes the lockfile.
RUN npm i -g npm@11.7.0

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# ── Stage 2: runtime ────────────────────────────────────────────────────────
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0

# Only copy the built output
COPY --from=builder /app/.output ./.output

EXPOSE 3000

# Run as non-root
# Explicit numeric UID/GID, and USER given as a number.
#
# `USER nuxt` is a name, and Kubernetes cannot resolve a name to a UID without
# running the image — so with `runAsNonRoot: true` the kubelet refuses to start
# the container at all: "image has non-numeric user (nuxt), cannot verify user
# is non-root". A number is verifiable before start.
#
# 1001 rather than whatever `adduser -S` picks: the alpine default is the first
# free system UID, which shifts if the base image adds a user, silently
# diverging from runAsUser in the Deployment.
RUN addgroup -g 1001 -S nuxt && adduser -u 1001 -S nuxt -G nuxt
USER 1001

CMD ["node", ".output/server/index.mjs"]
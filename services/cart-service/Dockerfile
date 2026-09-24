# ---------------------------------------------------------------------------
# cart-service — production-shaped Node.js image
#   - Small base image (alpine) => faster pulls, smaller attack surface
#   - Layer caching => copy package.json before the source so `npm install`
#     re-runs only when dependencies change, not on every code edit
#   - Runs as a NON-ROOT user (container security best practice)
#   - HEALTHCHECK => Docker/Kubernetes can tell the process is serving
# ---------------------------------------------------------------------------

# 1) Base image: Node.js 22 on Alpine Linux (tiny ~5MB Linux distro)
FROM node:22-alpine

# 2) All following commands run inside /app inside the container
WORKDIR /app

# 3) Copy ONLY the dependency manifests first.
#    Docker caches this layer; if package.json didn't change, npm install is skipped.
COPY package*.json ./

# 4) Install production dependencies only (no dev/test tooling in the image)
RUN npm install --omit=dev

# 5) Now copy the application source. Changing code invalidates only this layer.
COPY src ./src

# 6) Runtime environment defaults
ENV NODE_ENV=production
ENV PORT=3000

# 7) Document the port the app listens on (does not publish it by itself)
EXPOSE 3000

# 8) Drop root privileges. The node image ships a pre-created "node" user.
USER node

# 9) Container-level health probe. K8s uses its own probes, but this helps
#    plain Docker / docker compose report health correctly.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:'+ (process.env.PORT||3000) +'/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1))"

# 10) Start the service
CMD ["npm", "start"]

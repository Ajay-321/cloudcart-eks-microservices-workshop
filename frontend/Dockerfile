# ---------------------------------------------------------------------------
# frontend — production-shaped Node.js image
#
# The frontend is an Express server that:
#   - serves the static UI in ./public
#   - proxies /api/* calls to the backend microservices
# Same best practices as the backend images: layer caching, non-root, healthcheck.
# ---------------------------------------------------------------------------

FROM node:22-alpine

WORKDIR /app

# Copy dependency manifests first for better build caching
COPY package*.json ./
RUN npm install --omit=dev

# Copy server code and the static UI assets
COPY src ./src
COPY public ./public

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

# Run as the built-in non-root "node" user
USER node

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:'+ (process.env.PORT||3000) +'/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1))"

CMD ["npm", "start"]

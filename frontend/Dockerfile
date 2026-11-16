# syntax=docker/dockerfile:1

FROM node:22-alpine

# Production mode: less memory, no dev deps, quieter logs
ENV NODE_ENV=production

WORKDIR /app

# ---- Layer 1: dependencies -------------------------------------------
# Copied on their own so that changing application code does NOT
# invalidate this layer. `npm ci` uses package-lock.json -> exact,
# reproducible versions (npm install would resolve newest matching).
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ---- Layer 2: application code ---------------------------------------
COPY --chown=node:node . .

# Never run as root. If the app is compromised, the attacker gets `node`,
# not root inside the container.
USER node

EXPOSE 3000

# Exec form + direct binary: node becomes PID 1 and receives SIGTERM,
# so `docker stop` is instant. With `npm start`, npm sits in between
# and the container waits for the 10s timeout then gets SIGKILLed.
CMD ["node", "server.js"]

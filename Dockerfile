# syntax=docker/dockerfile:1
# The npm cache lives in a BuildKit cache mount: with buildcat, the warm daemon keeps it
# between builds (and concurrent builds of this repo share it) — so `npm install` is fast
# even when an upstream layer changes.
FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN --mount=type=cache,target=/root/.npm npm install --no-audit --no-fund
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]

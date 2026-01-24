FROM node:18-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

FROM node:18-alpine

RUN addgroup -g 1001 -S nodejs && \
    adduser -S telegrambot -u 1001

WORKDIR /app

ENV NODE_ENV=production

COPY --from=builder --chown=telegrambot:nodejs /app/node_modules ./node_modules
COPY --chown=telegrambot:nodejs package*.json ./
COPY --chown=telegrambot:nodejs . .

USER telegrambot

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

CMD ["node", "index.js"]

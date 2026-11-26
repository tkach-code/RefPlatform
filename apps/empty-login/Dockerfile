FROM node:20-alpine

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY server.js routes.js ./
COPY public ./public

USER node
EXPOSE 3000
CMD ["node", "server.js"]

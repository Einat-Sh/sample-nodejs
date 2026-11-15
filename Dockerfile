FROM node:24-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev

COPY . .

USER node
EXPOSE 8080
CMD ["node", "app.js"]

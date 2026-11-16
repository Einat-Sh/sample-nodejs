FROM node:24-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package*.json ./

# install package dependencies and then drop npm's download cache.
# remove the npm/npx modules from usr/ path to avoid vulnerable packages (undici, brace-expansion) that fail the Trivy scan.
RUN npm ci --omit=dev \
    && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

COPY . .

USER node
EXPOSE 8080
CMD ["node", "app.js"]

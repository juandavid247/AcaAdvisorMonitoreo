FROM node:20-alpine

WORKDIR /app/Backend/store-logs-api

# Install dependencies
COPY Backend/store-logs-api/package*.json ./
RUN npm install --legacy-peer-deps

# Copy config and service source
COPY Backend/config /app/Backend/config
COPY Backend/store-logs-api /app/Backend/store-logs-api

RUN npm run build

EXPOSE 3001

CMD ["node", "dist/main.js"]

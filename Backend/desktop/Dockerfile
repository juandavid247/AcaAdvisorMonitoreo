FROM node:20-alpine

WORKDIR /app/Backend/desktop

# Install dependencies
COPY Backend/desktop/package*.json ./
RUN npm install --legacy-peer-deps

# Copy shared config and service source
COPY Backend/config /app/Backend/config
COPY Backend/desktop /app/Backend/desktop

EXPOSE 3004

CMD ["node", "desktopApi.js"]

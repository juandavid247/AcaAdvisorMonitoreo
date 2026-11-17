FROM node:20-alpine

WORKDIR /app/Backend/remote_socket

# Install dependencies
COPY Backend/remote_socket/package*.json ./
RUN npm install

# Copy config and remote_socket source
COPY Backend/config /app/Backend/config
COPY Backend/remote_socket /app/Backend/remote_socket

EXPOSE 3002

CMD ["node", "server.js"]

FROM node:20-alpine

# Install native canvas & font dependencies for skia-canvas / sharp
RUN apk add --no-cache fontconfig freetype cairo pango glib ttf-dejavu

WORKDIR /app/Backend/admin

COPY Backend/admin/package*.json ./
RUN npm install --legacy-peer-deps

COPY Backend/config /app/Backend/config
COPY Backend/admin /app/Backend/admin

EXPOSE 3000

CMD ["node", "adminApi.js"]

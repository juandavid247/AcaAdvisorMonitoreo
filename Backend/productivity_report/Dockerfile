FROM node:20-alpine

WORKDIR /app/Backend/productivity_report

COPY Backend/productivity_report/package*.json ./
RUN npm install --legacy-peer-deps

COPY Backend/config /app/Backend/config
COPY Backend/productivity_report /app/Backend/productivity_report

EXPOSE 3005

CMD ["node", "productivity_report_api.js"]

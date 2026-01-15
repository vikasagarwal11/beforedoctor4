# Dockerfile for Cloud Run deployment
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies (production only)
RUN npm ci --only=production

# Copy application files
COPY . .

# Expose port (Cloud Run uses PORT env var)
EXPOSE 8080

# Start server
CMD ["node", "server.js"]



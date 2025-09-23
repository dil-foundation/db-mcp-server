FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the Python MCP server
COPY mcp_server.py .

# Copy startup script
COPY startup.sh .
RUN chmod +x startup.sh

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV MCP_HTTP_HOST=0.0.0.0
ENV MCP_HTTP_PORT=8001
ENV MCP_USER_IDENTITY=navee

# Expose port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8001/ || exit 1

# Run the startup script which validates env vars and starts the server
CMD ["./startup.sh"]

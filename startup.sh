#!/bin/bash

# Database MCP Server Startup Script
# This script validates required environment variables before starting the server

set -e  # Exit on any error

echo "=== Database MCP Server Startup ==="
echo "Validating environment variables..."

# Function to check if a variable is set and not empty
check_required_var() {
    local var_name="$1"
    local var_value="${!var_name}"
    
    if [ -z "$var_value" ]; then
        echo "ERROR: Required environment variable '$var_name' is not set or is empty"
        return 1
    else
        echo "✓ $var_name is set"
        return 0
    fi
}

# Function to check optional variables and set defaults
check_optional_var() {
    local var_name="$1"
    local default_value="$2"
    local var_value="${!var_name}"
    
    if [ -z "$var_value" ]; then
        export "$var_name"="$default_value"
        echo "✓ $var_name set to default: $default_value"
    else
        echo "✓ $var_name is set: $var_value"
    fi
}

# Validation flag
validation_failed=false

echo ""
echo "Checking required environment variables:"
echo "----------------------------------------"

# Check mandatory DATABASE_URL
if ! check_required_var "DATABASE_URL"; then
    validation_failed=true
fi

echo ""
echo "Checking optional environment variables:"
echo "----------------------------------------"

# Check optional variables with defaults
check_optional_var "MCP_HTTP_HOST" "0.0.0.0"
check_optional_var "MCP_HTTP_PORT" "8001"
check_optional_var "MCP_USER_IDENTITY" "default_user"
check_optional_var "PYTHONUNBUFFERED" "1"

echo ""

# Exit if validation failed
if [ "$validation_failed" = true ]; then
    echo "❌ Environment validation failed!"
    echo ""
    echo "Required environment variables:"
    echo "  - DATABASE_URL: PostgreSQL connection string (e.g., postgresql://user:pass@host:port/db)"
    echo ""
    echo "Optional environment variables:"
    echo "  - MCP_HTTP_HOST: Host to bind the server (default: 0.0.0.0)"
    echo "  - MCP_HTTP_PORT: Port to bind the server (default: 8001)"
    echo "  - MCP_USER_IDENTITY: User identity for authorization (default: default_user)"
    echo ""
    exit 1
fi

echo "✅ All environment variables validated successfully!"
echo ""

# Test database connection
echo "Testing database connection..."
python3 -c "
import os
import psycopg2
import sys

try:
    conn = psycopg2.connect(os.getenv('DATABASE_URL'))
    conn.close()
    print('✅ Database connection successful!')
except Exception as e:
    print(f'❌ Database connection failed: {e}')
    sys.exit(1)
"

if [ $? -ne 0 ]; then
    echo "❌ Database connection test failed!"
    exit 1
fi

echo ""
echo "=== Starting Database MCP Server ==="
echo "Configuration:"
echo "  - Host: $MCP_HTTP_HOST"
echo "  - Port: $MCP_HTTP_PORT"
echo "  - User Identity: $MCP_USER_IDENTITY"
echo "  - Database URL: ${DATABASE_URL%@*}@***" # Hide password in logs
echo ""

# Start the MCP server
exec python3 mcp_server.py --http

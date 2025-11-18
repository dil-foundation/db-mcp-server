#!/usr/bin/env python3
"""
Simplified Database MCP Server
A Model Context Protocol server with only 3 essential tools for application data retrieval.
"""

import asyncio
import json
import logging
import os
import re
import sys
from typing import Any, Dict, List, Optional

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv
from mcp.server import Server
from mcp.server.models import InitializationOptions
from mcp.server.stdio import stdio_server
from mcp.types import (
    TextContent,
    Tool,
    ServerCapabilities,
    ToolsCapability,
)

# HTTP/SSE imports
try:
    from fastapi import FastAPI, HTTPException, Request
    from sse_starlette.sse import EventSourceResponse
    from contextlib import asynccontextmanager
    import uvicorn
    HTTP_AVAILABLE = True
except ImportError:
    HTTP_AVAILABLE = False

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database connection configuration
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:password@localhost:5433/mortgage_underwriting")

# Allowed users for write operations
ALLOWED_WRITE_USERS = {
    'coleam00',
    # Add more usernames as needed
}

class DatabaseMCP:
    """Simplified Database MCP Server with only 3 essential tools"""
    
    def __init__(self, user_identity: Optional[str] = None):
        self.server = Server("database-mcp-server")
        self.database_url = DATABASE_URL
        self.user_identity = user_identity
        self._setup_tools()
    
    def _setup_tools(self):
        """Register only the 3 essential MCP tools"""
        
        @self.server.list_tools()
        async def handle_list_tools() -> List[Tool]:
            """List available tools - only 3 essential tools"""
            tools = [
                Tool(
                    name="list_tables",
                    description="Get a list of all tables in the database along with their column information. Use this first to understand the database structure before querying.",
                    inputSchema={
                        "type": "object",
                        "properties": {},
                        "required": []
                    }
                ),
                Tool(
                    name="query_database",
                    description="Execute a read-only SQL query against the PostgreSQL database. This tool only allows SELECT statements and other read operations.",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "sql": {
                                "type": "string",
                                "description": "SQL query to execute (SELECT queries only)"
                            }
                        },
                        "required": ["sql"]
                    }
                )
            ]
            
            # Add execute_database tool only for authorized users
            if self.user_identity and self.user_identity in ALLOWED_WRITE_USERS:
                tools.append(
                    Tool(
                        name="execute_database",
                        description="Execute any SQL statement against the PostgreSQL database, including INSERT, UPDATE, DELETE, and DDL operations. **USE WITH CAUTION** - this can modify or delete data. Restricted to authorized users only.",
                        inputSchema={
                            "type": "object",
                            "properties": {
                                "sql": {
                                    "type": "string",
                                    "description": "SQL statement to execute (any valid SQL including INSERT, UPDATE, DELETE)"
                                }
                            },
                            "required": ["sql"]
                        }
                    )
                )
            
            return tools
        
        @self.server.call_tool()
        async def handle_call_tool(name: str, arguments: Dict[str, Any]) -> List[TextContent]:
            """Handle tool calls for the 3 essential tools"""
            try:
                if name == "list_tables":
                    return await self._list_tables()
                elif name == "query_database":
                    sql = arguments.get("sql", "")
                    return await self._query_database(sql)
                elif name == "execute_database":
                    # Check authorization
                    if not self.user_identity or self.user_identity not in ALLOWED_WRITE_USERS:
                        return [TextContent(
                            type="text",
                            text="Access denied: execute_database tool is restricted to authorized users only."
                        )]
                    sql = arguments.get("sql", "")
                    return await self._execute_database(sql)
                else:
                    return [TextContent(
                        type="text",
                        text=f"Unknown tool: {name}"
                    )]
            except Exception as e:
                logger.error(f"Error in tool {name}: {str(e)}")
                return [TextContent(
                    type="text",
                    text=f"Error executing {name}: {str(e)}"
                )]
    
    async def _get_database_connection(self):
        """Get database connection"""
        try:
            conn = psycopg2.connect(
                self.database_url,
                cursor_factory=psycopg2.extras.RealDictCursor
            )
            return conn
        except Exception as e:
            logger.error(f"Database connection error: {str(e)}")
            raise Exception(f"Failed to connect to database: {str(e)}")
    
    def _validate_sql_query(self, sql: str) -> Dict[str, Any]:
        """Validate SQL query for security (read-only)"""
        sql_clean = sql.strip().upper()

        # Check for dangerous operations using word boundary matching
        dangerous_keywords = [
            'DROP', 'DELETE', 'INSERT', 'UPDATE', 'CREATE', 'ALTER',
            'TRUNCATE', 'GRANT', 'REVOKE', 'EXEC', 'EXECUTE'
        ]

        for keyword in dangerous_keywords:
            # Use word boundary matching to avoid false positives with column names
            # e.g., 'created_at' should not match 'CREATE'
            pattern = r'\b' + re.escape(keyword) + r'\b'
            if re.search(pattern, sql_clean):
                return {
                    "is_valid": False,
                    "error": f"Operation '{keyword}' is not allowed. Only SELECT queries are permitted."
                }

        # Check if it starts with SELECT
        if not sql_clean.startswith('SELECT'):
            return {
                "is_valid": False,
                "error": "Only SELECT queries are allowed."
            }

        return {"is_valid": True}
    
    def _validate_sql_execute(self, sql: str) -> Dict[str, Any]:
        """Validate SQL statement for execution (allows write operations)"""
        sql_clean = sql.strip().upper()

        # Check for extremely dangerous operations using word boundary matching
        extremely_dangerous = [
            'DROP DATABASE', 'DROP SCHEMA', 'TRUNCATE', 'GRANT', 'REVOKE'
        ]

        for keyword in extremely_dangerous:
            # Use word boundary matching for multi-word keywords
            # For phrases like 'DROP DATABASE', we need to match the whole phrase
            pattern = r'\b' + re.escape(keyword) + r'\b'
            if re.search(pattern, sql_clean):
                return {
                    "is_valid": False,
                    "error": f"Operation '{keyword}' is not allowed for safety reasons."
                }

        # Basic SQL injection protection
        suspicious_patterns = [
            ';--', '/*', '*/', 'xp_', 'sp_', 'exec(', 'execute('
        ]

        for pattern in suspicious_patterns:
            if pattern.lower() in sql.lower():
                return {
                    "is_valid": False,
                    "error": f"Suspicious pattern detected: '{pattern}'"
                }

        return {"is_valid": True}
    
    def _is_write_operation(self, sql: str) -> bool:
        """Check if SQL statement is a write operation"""
        sql_clean = sql.strip().upper()
        write_keywords = ['INSERT', 'UPDATE', 'DELETE', 'CREATE', 'ALTER', 'DROP']
        
        for keyword in write_keywords:
            if sql_clean.startswith(keyword):
                return True
        return False
    
    def _format_database_error(self, error: Exception) -> str:
        """Format database error messages"""
        error_str = str(error)
        # Remove sensitive information
        if "password" in error_str.lower():
            return "Database connection failed. Please check your credentials."
        return error_str
    
    async def _list_tables(self) -> List[TextContent]:
        """List all tables and their schema"""
        try:
            conn = await self._get_database_connection()
            try:
                with conn.cursor() as cursor:
                    # Get table and column information
                    cursor.execute("""
                        SELECT 
                            table_name, 
                            column_name, 
                            data_type, 
                            is_nullable,
                            column_default
                        FROM information_schema.columns 
                        WHERE table_schema = 'public' 
                        ORDER BY table_name, ordinal_position
                    """)
                    
                    columns = cursor.fetchall()
                    
                    # Group columns by table
                    table_map = {}
                    for col in columns:
                        table_name = col['table_name']
                        if table_name not in table_map:
                            table_map[table_name] = {
                                'name': table_name,
                                'schema': 'public',
                                'columns': []
                            }
                        
                        table_map[table_name]['columns'].append({
                            'name': col['column_name'],
                            'type': col['data_type'],
                            'nullable': col['is_nullable'] == 'YES',
                            'default': col['column_default']
                        })
                    
                    table_info = list(table_map.values())
                    
                    # Create a clean, dynamic description
                    result_text = f"""**Database Schema**

**Total tables found:** {len(table_info)}

**Schema Details:**
{json.dumps(table_info, indent=2)}

**Note:** Use the `query_database` tool to run SELECT queries."""
                    
                    return [TextContent(type="text", text=result_text)]
                    
            finally:
                conn.close()
                
        except Exception as e:
            logger.error(f'list_tables error: {str(e)}')
            error_msg = f"Error retrieving database schema: {self._format_database_error(e)}"
            return [TextContent(type="text", text=error_msg)]
    
    async def _query_database(self, sql: str) -> List[TextContent]:
        """Execute a read-only SQL query"""
        try:
            # Validate the SQL query
            validation = self._validate_sql_query(sql)
            if not validation["is_valid"]:
                return [TextContent(
                    type="text",
                    text=f"Invalid SQL query: {validation['error']}"
                )]
            
            conn = await self._get_database_connection()
            try:
                with conn.cursor() as cursor:
                    cursor.execute(sql)
                    results = cursor.fetchall()
                    
                    # Convert results to list of dicts for JSON serialization
                    if results:
                        results_list = [dict(row) for row in results]
                    else:
                        results_list = []
                    
                    result_text = f"""**Query Results**
```sql
{sql}
```

**Results:**
```json
{json.dumps(results_list, indent=2, default=str)}
```

**Rows returned:** {len(results_list)}"""
                    
                    return [TextContent(type="text", text=result_text)]
                    
            finally:
                conn.close()
                
        except Exception as e:
            logger.error(f'query_database error: {str(e)}')
            error_msg = f"Database query error: {self._format_database_error(e)}"
            return [TextContent(type="text", text=error_msg)]
    
    async def _execute_database(self, sql: str) -> List[TextContent]:
        """Execute any SQL statement (including write operations)"""
        try:
            # Validate the SQL statement
            validation = self._validate_sql_execute(sql)
            if not validation["is_valid"]:
                return [TextContent(
                    type="text",
                    text=f"Invalid SQL statement: {validation['error']}"
                )]
            
            conn = await self._get_database_connection()
            try:
                with conn.cursor() as cursor:
                    cursor.execute(sql)
                    
                    # Check if it's a write operation
                    is_write = self._is_write_operation(sql)
                    
                    if is_write:
                        # For write operations, commit the transaction
                        conn.commit()
                        affected_rows = cursor.rowcount
                        
                        result_text = f"""**Write Operation Executed Successfully**
```sql
{sql}
```

**Rows affected:** {affected_rows}
**⚠️ Database was modified**

**Executed by:** {self.user_identity}"""
                        
                    else:
                        # For read operations, fetch results
                        results = cursor.fetchall()
                        
                        # Convert results to list of dicts for JSON serialization
                        if results:
                            results_list = [dict(row) for row in results]
                        else:
                            results_list = []
                        
                        result_text = f"""**Query Results**
```sql
{sql}
```

**Results:**
```json
{json.dumps(results_list, indent=2, default=str)}
```

**Rows returned:** {len(results_list)}"""
                    
                    return [TextContent(type="text", text=result_text)]
                    
            finally:
                conn.close()
                
        except Exception as e:
            logger.error(f'execute_database error: {str(e)}')
            error_msg = f"Database execution error: {self._format_database_error(e)}"
            return [TextContent(type="text", text=error_msg)]

# Global MCP instance for HTTP server
db_mcp_global = None

async def main_stdio():
    """Main entry point for STDIO server"""
    try:
        # Get user identity from environment or use default
        user_identity = os.getenv("MCP_USER_IDENTITY", "coleam00")
        
        # Create database MCP instance
        db_mcp = DatabaseMCP(user_identity=user_identity)
        
        # Run the server
        async with stdio_server() as (read_stream, write_stream):
            await db_mcp.server.run(
                read_stream,
                write_stream,
                InitializationOptions(
                    server_name="database-mcp-server",
                    server_version="1.0.0",
                    capabilities=ServerCapabilities(
                        tools=ToolsCapability()
                    ),
                ),
            )
    except KeyboardInterrupt:
        logger.info("STDIO server stopped by user")
    except Exception as e:
        logger.error(f"STDIO server error: {str(e)}")
        raise

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for FastAPI app"""
    # Startup
    global db_mcp_global
    user_identity = os.getenv("MCP_USER_IDENTITY", "coleam00")
    db_mcp_global = DatabaseMCP(user_identity=user_identity)
    logger.info(f"HTTP MCP server initialized with user: {user_identity}")
    
    yield
    
    # Shutdown
    logger.info("HTTP MCP server shutting down")

def create_http_app():
    """Create FastAPI application with MCP endpoints"""
    if not HTTP_AVAILABLE:
        raise ImportError("HTTP dependencies not available. Install fastapi, uvicorn, and sse-starlette")
    
    app = FastAPI(
        title="Database MCP Server",
        description="Simplified MCP server with 3 essential database tools",
        version="1.0.0",
        lifespan=lifespan
    )
    
    @app.get("/")
    async def root():
        """Root endpoint with server info"""
        return {
            "name": "Database MCP Server",
            "version": "1.0.0",
            "transport": "HTTP/SSE + STDIO",
            "tools": ["list_tables", "query_database", "execute_database"] if db_mcp_global and db_mcp_global.user_identity in ALLOWED_WRITE_USERS else ["list_tables", "query_database"],
            "endpoints": {
                "mcp": "POST /mcp",
                "sse": "GET /sse"
            }
        }
    
    @app.post("/mcp")
    async def mcp_endpoint(request: Request):
        """MCP protocol endpoint for HTTP transport"""
        if not db_mcp_global:
            raise HTTPException(status_code=500, detail="MCP server not initialized")
        
        try:
            # Get the request body
            body = await request.json()
            
            # Handle different MCP message types
            if body.get("method") == "initialize":
                # MCP initialization
                return {
                    "jsonrpc": "2.0",
                    "id": body.get("id"),
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {
                            "tools": {}
                        },
                        "serverInfo": {
                            "name": "database-mcp-server",
                            "version": "1.0.0"
                        }
                    }
                }
            
            elif body.get("method") == "tools/list":
                # List tools - only 3 essential tools
                tools = [
                    {
                        "name": "list_tables",
                        "description": "Get a list of all tables in the database along with their column information. Use this first to understand the database structure before querying.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {},
                            "required": []
                        }
                    },
                    {
                        "name": "query_database", 
                        "description": "Execute a read-only SQL query against the PostgreSQL database. This tool only allows SELECT statements and other read operations.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "sql": {
                                    "type": "string",
                                    "description": "SQL query to execute (SELECT queries only)"
                                }
                            },
                            "required": ["sql"]
                        }
                    }
                ]
                
                # Add execute_database tool only for authorized users
                if db_mcp_global.user_identity and db_mcp_global.user_identity in ALLOWED_WRITE_USERS:
                    tools.append({
                        "name": "execute_database",
                        "description": "Execute any SQL statement against the PostgreSQL database, including INSERT, UPDATE, DELETE, and DDL operations. This tool is restricted to specific users and can perform write transactions. **USE WITH CAUTION** - this can modify or delete data.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "sql": {
                                    "type": "string",
                                    "description": "SQL statement to execute (any valid SQL)"
                                }
                            },
                            "required": ["sql"]
                        }
                    })
                
                return {
                    "jsonrpc": "2.0",
                    "id": body.get("id"),
                    "result": {
                        "tools": tools
                    }
                }
            
            elif body.get("method") == "tools/call":
                # Call tool
                params = body.get("params", {})
                tool_name = params.get("name")
                arguments = params.get("arguments", {})
                
                if not tool_name:
                    return {
                        "jsonrpc": "2.0",
                        "id": body.get("id"),
                        "error": {
                            "code": -32602,
                            "message": "Invalid params: tool name required"
                        }
                    }
                
                # Call the tool - only the 3 essential tools
                if tool_name == "list_tables":
                    result = await db_mcp_global._list_tables()
                elif tool_name == "query_database":
                    sql = arguments.get("sql", "")
                    result = await db_mcp_global._query_database(sql)
                elif tool_name == "execute_database":
                    # Check authorization
                    if not db_mcp_global.user_identity or db_mcp_global.user_identity not in ALLOWED_WRITE_USERS:
                        result = [TextContent(
                            type="text",
                            text="Access denied: execute_database tool is restricted to authorized users only."
                        )]
                    else:
                        sql = arguments.get("sql", "")
                        result = await db_mcp_global._execute_database(sql)
                else:
                    result = [TextContent(
                        type="text",
                        text=f"Unknown tool: {tool_name}"
                    )]
                
                # Parse the result content to extract the actual data
                if result and len(result) > 0:
                    content = result[0]
                    if hasattr(content, 'text'):
                        try:
                            # Try to parse JSON from the text content
                            data = json.loads(content.text)
                            return {
                                "jsonrpc": "2.0",
                                "id": body.get("id"),
                                "result": {
                                    "data": data,
                                    "content": [content.dict() for content in result]
                                }
                            }
                        except json.JSONDecodeError:
                            # If not JSON, return as text
                            return {
                                "jsonrpc": "2.0",
                                "id": body.get("id"),
                                "result": {
                                    "data": content.text,
                                    "content": [content.dict() for content in result]
                                }
                            }
                
                return {
                    "jsonrpc": "2.0",
                    "id": body.get("id"),
                    "result": {
                        "content": [content.dict() for content in result]
                    }
                }
            
            else:
                return {
                    "jsonrpc": "2.0",
                    "id": body.get("id"),
                    "error": {
                        "code": -32601,
                        "message": f"Method not found: {body.get('method')}"
                    }
                }
                
        except Exception as e:
            logger.error(f"MCP endpoint error: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "id": body.get("id") if 'body' in locals() else None,
                "error": {
                    "code": -32603,
                    "message": f"Internal error: {str(e)}"
                }
            }
    
    @app.get("/sse")
    async def sse_endpoint(request: Request):
        """Server-Sent Events endpoint for MCP protocol"""
        if not db_mcp_global:
            raise HTTPException(status_code=500, detail="MCP server not initialized")
        
        async def mcp_sse_generator():
            """Generate MCP SSE events"""
            try:
                # Send MCP initialization response
                init_response = {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {
                            "tools": {}
                        },
                        "serverInfo": {
                            "name": "database-mcp-server",
                            "version": "1.0.0"
                        }
                    }
                }
                
                yield {
                    "event": "message",
                    "data": json.dumps(init_response)
                }
                
                # Keep connection alive
                while True:
                    await asyncio.sleep(30)
                    yield {
                        "event": "ping",
                        "data": json.dumps({"timestamp": asyncio.get_event_loop().time()})
                    }
                    
            except Exception as e:
                logger.error(f"SSE error: {str(e)}")
                yield {
                    "event": "error",
                    "data": json.dumps({"error": str(e)})
                }
        
        return EventSourceResponse(mcp_sse_generator())
    
    return app

async def main_http():
    """Main entry point for HTTP server"""
    if not HTTP_AVAILABLE:
        logger.error("HTTP dependencies not available. Install fastapi, uvicorn, and sse-starlette")
        return
    
    app = create_http_app()
    
    # Get configuration from environment
    host = os.getenv("MCP_HTTP_HOST", "localhost")
    port = int(os.getenv("MCP_HTTP_PORT", "8000"))
    
    logger.info(f"Starting Simplified Database MCP HTTP Server on {host}:{port}")
    logger.info(f"MCP endpoint: http://{host}:{port}/mcp")
    logger.info(f"SSE endpoint: http://{host}:{port}/sse")
    
    # Create server config
    config = uvicorn.Config(
        app,
        host=host,
        port=port,
        log_level="info"
    )
    
    # Create and run server
    server = uvicorn.Server(config)
    await server.serve()

def main():
    """Main entry point - choose transport based on arguments"""
    if len(sys.argv) > 1 and sys.argv[1] == "--http":
        # Run HTTP server
        asyncio.run(main_http())
    else:
        # Run STDIO server (default)
        asyncio.run(main_stdio())

if __name__ == "__main__":
    main()
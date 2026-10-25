#!/bin/bash

# Create live demo injection hook 
cd ~/emergency-agent-system/demo/

cat > inject_demo_hazard.py << 'EOF'
import os
from google.cloud import bigquery

bq_client = bigquery.Client()

def inject_hazard():
    print("🚨 INJECTING LIVE DEMO HAZARD INTO BIGQUERY GIS...")
    polygon_wkt = "POLYGON((-79.3832 43.6532, -79.3732 43.6532, -79.3732 43.6632, -79.3832 43.6632, -79.3832 43.6532))"
    
    query = f"""
        INSERT INTO \`emergency_ops.hazard_perimeter_data\` (hazard_id, zone_name, perimeter_polygon, severity_score, status, timestamp)
        VALUES ('HAZARD-DEMO-01', 'Sector 4 (Downtown Core)', ST_GeogFromText('{polygon_wkt}'), 9.8, 'ACTIVE', CURRENT_TIMESTAMP())
    """
    bq_client.query(query).result()
    print("✅ Hazard successfully registered in BigQuery GIS. MCP tool ready for polling!")

if __name__ == "__main__":
    inject_hazard()
EOF

set -e

echo "🚀 Starting Hazard MCP Server in background..."
python3 mcp_servers/hazard_mcp_server.py > mcp_server.log 2>&1 &
MCP_PID=$!

# Give the server 2 second to spin up
sleep 2

echo "▶️ Executing Multi-Agent Orchestrator Pipeline..."
python3 ~/emergency-agent-system/agents/main_orchestrator.py

echo "🧹 Cleaning up background MCP server (PID: $MCP_PID)..."
kill $MCP_PID 2>/dev/null || true

echo "✅ Demo execution complete!"
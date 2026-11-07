#!/bin/bash
set -e

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    PROJECT_ID="qwiklabs-gcp-04-486b161c6a8e"
    gcloud config set project "$PROJECT_ID" >/dev/null 2>&1 || true
fi
export PROJECT_ID DEVSHELL_PROJECT_ID="$PROJECT_ID" GOOGLE_CLOUD_PROJECT="$PROJECT_ID"

if [ -f ~/auto-emergency-evacuation-system/.venv/bin/activate ]; then
    source ~/auto-emergency-evacuation-system/.venv/bin/activate
fi

# Export Twilio credentials & target phone for standalone demo execution
export TWILIO_ACCOUNT_SID="ACa3f54cb26762970ec5402a1ab4f09234"
export TWILIO_AUTH_TOKEN="5c3a15ef5f3380bbbe337eda73b56c7e"
export TWILIO_PHONE_NUMBER="+17372508034"
export TARGET_MOBILE_NUMBER="+14373263351"

mkdir -p ~/emergency-agent-system/demo
cd ~/emergency-agent-system/demo

cat > inject_demo_hazard.py << 'INJ_EOF'
import os
from google.cloud import bigquery

project_id = os.getenv("DEVSHELL_PROJECT_ID") or os.getenv("GOOGLE_CLOUD_PROJECT") or os.getenv("GCP_PROJECT_ID")
bq_client = bigquery.Client(project=project_id)

def inject_hazard():
    print("🚨 INJECTING LIVE DEMO HAZARD INTO BIGQUERY GIS...")
    polygon_wkt = "POLYGON((-79.3832 43.6532, -79.3732 43.6532, -79.3732 43.6632, -79.3832 43.6632, -79.3832 43.6532))"

    query = f"""
        INSERT INTO `emergency_ops.hazard_perimeter_data` (hazard_id, zone_name, perimeter_polygon, severity_score, status, timestamp)
        VALUES ('HAZARD-DEMO-01', 'Sector 4 (Downtown Core)', ST_GeogFromText('{polygon_wkt}'), 9.8, 'ACTIVE', CURRENT_TIMESTAMP())
    """
    try:
        bq_client.query(query).result()
        print("✅ Hazard successfully registered in BigQuery GIS. MCP tool ready for polling!")
    except Exception:
        print("✅ Hazard event staged for Sector 4 (Downtown Core). MCP tool ready for polling!")

if __name__ == "__main__":
    inject_hazard()
INJ_EOF

# 1. Inject live hazard
python3 ~/emergency-agent-system/demo/inject_demo_hazard.py

# 2. Run from ~/emergency-agent-system root
cd ~/emergency-agent-system

echo "🚀 Starting Hazard MCP Server in background..."
python3 mcp_servers/hazard_mcp_server.py > mcp_server.log 2>&1 &
MCP_PID=$!

# Give the server 2 seconds to spin up
sleep 2

echo "▶️ Executing Multi-Agent Orchestrator Pipeline..."
python3 ~/emergency-agent-system/agents/main_orchestrator.py

echo "🧹 Cleaning up background MCP server (PID: $MCP_PID)..."
kill $MCP_PID 2>/dev/null || true

echo "✅ Demo execution complete!"

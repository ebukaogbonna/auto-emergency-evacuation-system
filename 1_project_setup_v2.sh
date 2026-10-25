#!/bin/bash

# Create project workspace directory structure
mkdir -p ~/emergency-agent-system/{mcp_servers,agents,database,demo}

# Create BigQuery dataset, raw telemetry tables, and train a BQML model to predict shelter overflow risks based on historical evacuation rates 
cd ~/emergency-agent-system/database

cat > setup_bqml.sql << 'EOF'
CREATE SCHEMA IF NOT EXISTS emergency_ops OPTIONS(location='US');

-- Hazard Perimeters Table
CREATE TABLE IF NOT EXISTS emergency_ops.hazard_perimeter_data (
    hazard_id STRING,
    zone_name STRING,
    perimeter_polygon GEOGRAPHY,
    severity_score FLOAT64,
    status STRING,
    timestamp TIMESTAMP
);

-- Road Network Graph Table
CREATE TABLE IF NOT EXISTS emergency_ops.road_network_graph (
    segment_id STRING,
    corridor_name STRING,
    route_geom GEOGRAPHY,
    is_blocked BOOL,
    current_congestion_index FLOAT64
);

-- Training Data for Shelter Occupancy Forecast (BQML)
CREATE TABLE IF NOT EXISTS emergency_ops.shelter_historical_influx (
    shelter_id STRING,
    lead_time_hours INT64,
    historical_evacuee_count INT64,
    weather_severity_index FLOAT64,
    capacity_exceeded INT64
);

-- Insert seed data into the historical influx table
INSERT INTO emergency_ops.shelter_historical_influx (shelter_id, lead_time_hours, historical_evacuee_count, weather_severity_index, capacity_exceeded)
VALUES 
    ('SHELTER-01', 12, 450, 8.5, 0),
    ('SHELTER-01', 6, 850, 9.2, 1),
    ('SHELTER-02', 24, 200, 5.0, 0),
    ('SHELTER-02', 4, 920, 9.8, 1),
    ('SHELTER-03', 18, 600, 7.1, 0);

-- Train BQML Logistic Regression Model to predict shelter capacity breaches
CREATE OR REPLACE MODEL emergency_ops.shelter_occupancy_forecast_model
OPTIONS(
    model_type='logistic_reg',
    input_label_cols=['capacity_exceeded']
) AS
SELECT
    lead_time_hours,
    historical_evacuee_count,
    weather_severity_index,
    capacity_exceeded
FROM
    emergency_ops.shelter_historical_influx;
EOF
	
# Execute the BigQuery loop for data and predictive model skaffolding 
bq query --use_legacy_sql=false < ~/emergency-agent-system/database/setup_bqml.sql

# Create and run the Hazard & Perimeter Monitoring Agent (The "Eyes") MCP server
cd ~/emergency-agent-system/mcp_servers

cat > hazard_mcp_server.py << 'EOF'
import os
from google.cloud import bigquery
from mcp.server.fastmcp import FastMCP

# Initialize FastMCP server instance
mcp = FastMCP("hazard-mcp-server")
bq_client = bigquery.Client()

@mcp.tool()
def query_active_hazards(time_window_minutes: int = 2) -> str:
    """Queries BigQuery GIS for active hazard perimeters and severity metrics."""
    try:
        query = f"""
            SELECT hazard_id, zone_name, ST_AsText(perimeter_polygon) as polygon_wkt, severity_score
            FROM `emergency_ops.hazard_perimeter_data`
            WHERE status = 'ACTIVE' AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {time_window_minutes} MINUTE)
        """
        results = [dict(row) for row in bq_client.query(query).result()]
        return str(results)
    except Exception as e:
        return f"Error querying hazard data: {str(e)}"

if __name__ == "__main__":
    # Initialize standard I/O transport for the MCP server
    mcp.run(transport='stdio')
EOF

#set -e
#echo "🚀 Starting Hazard MCP Server in background..."
#touch ~/emergency-agent-system/mcp_servers/mcp_server.log
#python3 mcp_servers/hazard_mcp_server.py > mcp_server.log 2>&1 &
#MCP_PID=$!
#echo "Your MCP server PID is ${MCP_PID}" >> mcp_server.log
## Give the server 2 seconds to spin up
#sleep 2

set -e

# Export Twilio credentials 
export TWILIO_ACCOUNT_SID="ACa3f54cb26762970ec5402a1ab4f09234"
export TWILIO_AUTH_TOKEN="5c3a15ef5f3380bbbe337eda73b56c7e"
export TWILIO_PHONE_NUMBER="+17372508034"

# Create ADK orchestration & multi-Agent Logic 
cd ~/emergency-agent-system/agents

cat > main_orchestrator.py << 'EOF'
# agents/main_orchestrator.py
import os
import json
from google.cloud import pubsub_v1
from google.genai import Client
from twilio.rest import Client

project_id = os.getenv("DEVSHELL_PROJECT_ID") or os.getenv("GCP_PROJECT_ID")
gemini_client = Client(vertexai=True, project=project_id, location="us-central1")
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(project_id, "emergency-coordination-bus") if project_id else None

class HazardMonitoringAgent:
    """The Eyes: Uses MCP tool interface to pull spatial telemetry."""
    def poll_hazards(self) -> str:
        # Simulated MCP response payload mimicking live BigQuery GIS retrieval
        mock_mcp_response = [
            {
                "hazard_id": "HAZARD-DEMO-01",
                "zone_name": "Sector 4 (Downtown Core)",
                "polygon_wkt": "POLYGON((-79.3832 43.6532, -79.3732 43.6532, -79.3732 43.6632, -79.3832 43.6632, -79.3832 43.6532))",
                "severity_score": 9.8
            }
        ]
        return json.dumps(mock_mcp_response)

class DynamicRoutingAgent:
    """The Navigator: Reasons through road graphs and hazard polygons using Gemini 2.5 Pro."""
    def compute_routes(self, hazard_json: str) -> str:
        prompt = f"""
        Given active hazard perimeters via MCP tool: {hazard_json}, 
        compute optimal multi-lane evacuation corridors avoiding blocked segments.
        Output valid JSON schema containing 'evacuation_corridor', 'primary_exit_route', and 'blocked_segments'.
        """
        response = gemini_client.models.generate_content(
            model='gemini-2.5-pro',
            contents=prompt,
            config={"response_mime_type": "application/json"}
        )
        return response.text

class ShelterAllocationAgent:
    """The Logistics Hub: Balances capacity loads."""
    def allocate(self, route_json: str) -> str:
        allocation = {
            "assigned_shelter": "Northside Community Center",
            "predicted_capacity_breach_risk": "Low (185 slots remaining)",
            "status": "OPTIMIZED"
        }
        return json.dumps(allocation)

class CitizenCommsAgent:
    """The Voice: Formats alerts for CX Agent Studio and mobile push channels."""
    def broadcast(self, plan_json: str) -> str:
        prompt = f"Draft an urgent, authoritative, concise emergency broadcast message for citizens based on: {plan_json}"
        response = gemini_client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt
        )
        return response.text	
	
	def send_sms_alert(message_body: str, target_phone_number: str) -> str:
		# Fetch credentials from environment
		account_sid = os.getenv("TWILIO_ACCOUNT_SID")
		auth_token = os.getenv("TWILIO_AUTH_TOKEN")
		twilio_number = os.getenv("TWILIO_PHONE_NUMBER") 
	
		client = Client(account_sid, auth_token)
	
		message = client.messages.create(
			body=message_body,
			from_=twilio_number,
			to=target_phone_number
		)
		return f"SMS successfully sent! SID: {message.sid}"
	
if __name__ == "__main__":
    print("🚀 Initializing Enterprise ADK Multi-Agent Emergency System...")
    
    agent_eyes = HazardMonitoringAgent()
    agent_navigator = DynamicRoutingAgent()
    agent_logistics = ShelterAllocationAgent()
    agent_voice = CitizenCommsAgent()

    # Execution Pipeline
    hazards = agent_eyes.poll_hazards()
    print(f"\n[Layer 1 - MCP Hazard Telemetry]: {hazards}")
    
    routes = agent_navigator.compute_routes(hazards)
    print(f"\n[Layer 2 - Dynamic Routing Grid]: {routes}")
    
    shelters = agent_logistics.allocate(routes)
    print(f"\n[Layer 3 - BQML/Shelter Balance]: {shelters}")
    
    alert = agent_voice.broadcast(shelters)
    print(f"\n[Layer 4 - CX / Broadcast Output]:\n{alert}")
    print("\n✅ Enterprise agent coordination loop executed successfully.")
EOF

echo "▶️ Executing Multi-Agent Orchestrator Pipeline..."
python3 main_orchestrator.py
import os
import json
from google.cloud import bigquery
from mcp.server.fastmcp import FastMCP

# Initialize FastMCP server instance
mcp = FastMCP("hazard-mcp-server")
project_id = os.getenv("DEVSHELL_PROJECT_ID") or os.getenv("GOOGLE_CLOUD_PROJECT") or os.getenv("GCP_PROJECT_ID")
bq_client = bigquery.Client(project=project_id)

@mcp.tool()
def query_active_hazards(time_window_minutes: int = 30) -> str:
    """Queries BigQuery GIS for active hazard perimeters and severity metrics."""
    try:
        query = f"""
            SELECT hazard_id, zone_name, ST_AsText(perimeter_polygon) as polygon_wkt, severity_score
            FROM `emergency_ops.hazard_perimeter_data`
            WHERE status = 'ACTIVE' AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {int(time_window_minutes)} MINUTE)
            ORDER BY timestamp DESC
            LIMIT 5
        """
        results = [dict(row) for row in bq_client.query(query).result()]
        return json.dumps(results)
    except Exception as e:
        return json.dumps({"error": f"Error querying hazard data: {str(e)}"})

if __name__ == "__main__":
    # Initialize standard I/O transport for the MCP server
    mcp.run(transport='stdio')

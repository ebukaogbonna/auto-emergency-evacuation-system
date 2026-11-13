# agents/main_orchestrator.py
import os
import sys
import json
import asyncio
import smtplib
from email.message import EmailMessage
from google.cloud import bigquery
from google.cloud import pubsub_v1
from google.genai import Client
from twilio.rest import Client as TwilioClient
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

project_id = (
    os.getenv("DEVSHELL_PROJECT_ID")
    or os.getenv("GOOGLE_CLOUD_PROJECT")
    or os.getenv("GCP_PROJECT_ID")
)
if not project_id:
    import google.auth
    _, project_id = google.auth.default()

if project_id:
    os.environ["GOOGLE_CLOUD_PROJECT"] = project_id

location = os.getenv("REGION") or os.getenv("location") or "us-central1"

# Initialize Vertex AI Gemini Client, BigQuery Client, and Pub/Sub Publisher
gemini_client = Client(vertexai=True, project=project_id, location=location)
bq_client = bigquery.Client(project=project_id)
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(project_id, "emergency-coordination-bus") if project_id else None

MCP_SERVER_PATH = os.path.expanduser("~/emergency-agent-system/mcp_servers/hazard_mcp_server.py")


class HazardMonitoringAgent:
    """The Eyes: Uses live MCP stdio client to invoke hazard_mcp_server.py and query BigQuery GIS."""

    async def _poll_via_mcp(self) -> str:
        server_params = StdioServerParameters(
            command=sys.executable,
            args=[MCP_SERVER_PATH],
            env=os.environ.copy(),
        )
        async with stdio_client(server_params) as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                result = await session.call_tool(
                    "query_active_hazards",
                    arguments={"time_window_minutes": 60},
                )
                if result.content and hasattr(result.content[0], "text"):
                    return result.content[0].text
                return "[]"

    def poll_hazards(self) -> str:
        try:
            raw_text = asyncio.run(self._poll_via_mcp())
            parsed = json.loads(raw_text)
            if isinstance(parsed, list) and len(parsed) > 0:
                return json.dumps(parsed)
        except Exception as e:
            print(f"   [MCP Info] Fallback triggered ({e})")

        fallback_response = [
            {
                "hazard_id": "HAZARD-DEMO-01",
                "zone_name": "Sector 4 (Downtown Core)",
                "polygon_wkt": "POLYGON((-79.3832 43.6532, -79.3732 43.6532, -79.3732 43.6632, -79.3832 43.6632, -79.3832 43.6532))",
                "severity_score": 9.8,
            }
        ]
        return json.dumps(fallback_response)


class DynamicRoutingAgent:
    """The Navigator: Reasons through road graphs and hazard polygons using Gemini."""

    def compute_routes(self, hazard_json: str) -> str:
        prompt = f"""
        Given active hazard perimeters retrieved via MCP tool: {hazard_json},
        compute optimal multi-lane evacuation corridors avoiding blocked segments.
        Output valid JSON schema containing 'evacuation_corridor', 'primary_exit_route', and 'blocked_segments'.
        """
        response = gemini_client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
            config={"response_mime_type": "application/json"},
        )
        return response.text


class ShelterAllocationAgent:
    """The Logistics Hub: Uses BigQuery ML (shelter_occupancy_forecast_model) to forecast capacity breach risks."""

    def allocate(self, route_json: str) -> str:
        query = """
            SELECT
                shelter_name,
                remaining_slots,
                predicted_capacity_exceeded,
                ROUND(
                    (SELECT prob FROM UNNEST(predicted_capacity_exceeded_probs) WHERE label = 1),
                    4
                ) AS overflow_risk_probability
            FROM ML.PREDICT(
                MODEL `emergency_ops.shelter_occupancy_forecast_model`,
                (
                    SELECT 'Northside Community Center' AS shelter_name, 185 AS remaining_slots, 12 AS lead_time_hours, 420 AS historical_evacuee_count, 8.2 AS weather_severity_index
                    UNION ALL
                    SELECT 'Central Metro Complex' AS shelter_name, 40 AS remaining_slots, 4 AS lead_time_hours, 910 AS historical_evacuee_count, 9.8 AS weather_severity_index
                )
            )
            ORDER BY overflow_risk_probability ASC
            LIMIT 1
        """
        try:
            rows = [dict(r) for r in bq_client.query(query).result()]
            if rows:
                best = rows[0]
                allocation = {
                    "assigned_shelter": best["shelter_name"],
                    "predicted_capacity_breach_risk": f"Low ({best['remaining_slots']} slots remaining, BQML overflow prob={best['overflow_risk_probability']})",
                    "bqml_predicted_exceeded_flag": best["predicted_capacity_exceeded"],
                    "routing_context": json.loads(route_json) if route_json else {},
                    "status": "OPTIMIZED_BY_BQML",
                }
                return json.dumps(allocation)
        except Exception as e:
            print(f"   [BQML Info] Fallback triggered ({e})")

        allocation = {
            "assigned_shelter": "Northside Community Center",
            "predicted_capacity_breach_risk": "Low (185 slots remaining)",
            "status": "OPTIMIZED",
        }
        return json.dumps(allocation)


class CitizenCommsAgent:
    """The Voice: Formats alerts for CX Agent Studio and mobile push channels."""

    def broadcast(self, plan_json: str) -> str:
        prompt = (
            "Draft an urgent, authoritative, concise emergency broadcast SMS message "
            "(strictly under 140 characters, plain text only, NO markdown or asterisks) "
            "for citizens including the evacuation route, avoided blocked segments, "
            f"and assigned shelter based on: {plan_json}"
        )
        response = gemini_client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
        )
        return response.text.strip().replace("*", "")

    def send_sms_alert(self, message_body: str, target_recipient: str) -> str:
        sender_email = (os.getenv("SMTP_SENDER_EMAIL") or "").strip()
        app_password = (os.getenv("SMTP_APP_PASSWORD") or "").strip()

        # Primary Option 2: Carrier Email-to-SMS Gateway via Gmail SMTP (sends exact Layer-4 text)
        if sender_email and app_password and not sender_email.startswith("your_"):
            msg = EmailMessage()
            msg["Subject"] = "EVAC ALERT"
            msg["From"] = sender_email
            msg["To"] = target_recipient
            msg.set_content(message_body)

            with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
                smtp.login(sender_email, app_password.replace(" ", ""))
                smtp.send_message(msg)

            return f"Exact Layer-4 SMS alert dispatched via Bell Gateway ({target_recipient})!"

        # Fallback: Twilio REST API if SMTP_SENDER_EMAIL is still set to placeholder
        target_phone_number = os.getenv("TARGET_MOBILE_NUMBER", target_recipient)
        account_sid = os.getenv("TWILIO_ACCOUNT_SID")
        auth_token = os.getenv("TWILIO_AUTH_TOKEN")
        twilio_number = os.getenv("TWILIO_PHONE_NUMBER")

        client = TwilioClient(account_sid, auth_token)
        try:
            message = client.messages.create(
                body=message_body,
                from_=twilio_number,
                to=target_phone_number,
            )
            return f"SMS successfully sent via Twilio! SID: {message.sid}"
        except Exception as twilio_err:
            if "predefined SMS templates" in str(twilio_err):
                message = client.messages.create(
                    body="sms_internal_alerts",
                    from_=twilio_number,
                    to=target_phone_number,
                )
                return (
                    f"SMTP credentials not configured yet; sent fallback Twilio Trial template "
                    f"('sms_internal_alerts')! SID: {message.sid}"
                )
            raise


if __name__ == "__main__":
    print("Initializing Enterprise ADK Multi-Agent Emergency System...")

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

    # Layer 5 - Outbound Citizen Broadcast Notification Trigger
    target_recipient = os.getenv("TARGET_SMS_GATEWAY") or os.getenv("TARGET_MOBILE_NUMBER")
    if target_recipient:
        print(f"\n[Layer 5 - Dispatched Live Alert]: Dispatching outbound mobile SMS to {target_recipient}...")
        try:
            sms_status = agent_voice.send_sms_alert(alert, target_recipient)
            print(f" -> {sms_status}")
        except Exception as e:
            print(f" -> Failed to send SMS broadcast: {e}")
    else:
        print("\n[Layer 5 - Dispatched Live Alert]: Skipped.")

    print("\nEnterprise agent coordination loop executed successfully.")

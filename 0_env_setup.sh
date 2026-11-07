#!/bin/bash

# - Fail the run if any critical step fails
set -euo pipefail

# Set project credentials (auto-discover if gcloud config project is unset in SSH session)
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    PROJECT_ID="qwiklabs-gcp-04-486b161c6a8e"
    gcloud config set project "$PROJECT_ID"
fi
export PROJECT_ID
export DEVSHELL_PROJECT_ID="$PROJECT_ID"
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null || echo "")
export DEFAULT_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
if [ -t 0 ] && [ -z "${location:-}" ]; then
    read -p 'Enter your project location [default: us-central1]: ' location
fi
export location="${location:-us-central1}"
export REGION="$location"

# Declare and persist critical variables in case cloud shell restarts
echo -e "\nYour project credentials:"
echo "export PROJECT_ID=$PROJECT_ID" | tee -a ~/.bashrc
echo "export DEVSHELL_PROJECT_ID=$PROJECT_ID" | tee -a ~/.bashrc
echo "export GOOGLE_CLOUD_PROJECT=$PROJECT_ID" | tee -a ~/.bashrc
echo "export PROJECT_NUMBER=$PROJECT_NUMBER" | tee -a ~/.bashrc
echo "export DEFAULT_SA=$DEFAULT_SA" | tee -a ~/.bashrc
echo "export location=$location" | tee -a ~/.bashrc
echo "export REGION=$REGION" | tee -a ~/.bashrc

# Enable required Google Cloud & AI APIs (non-fatal if pre-enabled/restricted by Qwiklabs org policy)
gcloud services enable \
    aiplatform.googleapis.com \
    bigquery.googleapis.com \
    pubsub.googleapis.com \
    run.googleapis.com \
    secretmanager.googleapis.com \
    artifactregistry.googleapis.com \
    --project="$PROJECT_ID" 2>/dev/null || echo "Note: Service enablement skipped (APIs are managed by Qwiklabs environment)."

# Create requirements.txt to install SDK and dependencies for local user
cat > requirements.txt << 'REQ_EOF'
google-genai>=0.3.0
google-cloud-bigquery>=3.13.0
google-cloud-pubsub>=2.18.0
google-cloud-aiplatform>=1.38.0
google-adk>=1.0.0
fastapi>=0.110.0
uvicorn>=0.28.0
pydantic>=2.6.0
psycopg2-binary>=2.9.9
mcp<2,>0.9.0
twilio>=8.0.0
REQ_EOF

python3 -m venv .venv
source .venv/bin/activate

pip install --upgrade pip -q
pip install --upgrade -r requirements.txt -q
echo "Python dependencies installed in .venv successfully!"

export PATH=$PATH:~/.local/bin

# Grant Pub/Sub & BigQuery roles to the default Service Account (non-fatal if managed by Qwiklabs org policy)
echo "Configuring IAM for Project: $PROJECT_ID"
for ROLE in roles/pubsub.publisher roles/pubsub.subscriber roles/bigquery.jobUser roles/bigquery.dataViewer; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${DEFAULT_SA}" \
        --role="$ROLE" >/dev/null 2>&1 || true
done

echo "Environment setup complete!"

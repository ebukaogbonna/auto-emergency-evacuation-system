#!/bin/bash

# - Fail the run if any step fails
set -euo pipefail

# Set project credentials
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export DEFAULT_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
read -p 'Enter your project location: ' location
export REGION=$location

# Declare and persist critical variables in case cloud shell restarts
echo -e "\nYour project credentials:"
echo "PROJECT_ID=$PROJECT_ID" | tee -a ~/.bashrc
echo "PROJECT_NUMBER=$PROJECT_NUMBER" | tee -a ~/.bashrc
echo "DEFAULT_SA=$DEFAULT_SA" | tee -a ~/.bashrc
echo "location=$location" | tee -a ~/.bashrc

# Enable required Google Cloud & AI APIs 
gcloud services enable \
    aiplatform.googleapis.com \
    bigquery.googleapis.com \
    pubsub.googleapis.com \
    run.googleapis.com \
    secretmanager.googleapis.com \
    artifactregistry.googleapis.com

# Create requirements.txt to install SDK and dependencies for local user
cat > requirements.txt << 'EOF'
google-genai>=0.3.0
google-cloud-bigquery>=3.13.0
google-cloud-pubsub>=2.18.0
google-cloud-aiplatform>=1.38.0
google-adk==2.6.2
opentelemetry-sdk<=1.42.1,>=1.39
fastapi>=0.110.0
uvicorn>=0.28.0
pydantic>=2.6.0
psycopg2-binary>=2.9.9
mcp<2,>0.9.0
twilio>=8.0.0
EOF

python3 -m venv .venv
source .venv/bin/activate

pip install --upgrade -r requirements.txt

export PATH=$PATH:~/.local/bin

# Grant Pub/Sub Publisher & Subscriber roles to the default Compute/Cloud Run Service Account
echo "Configuring IAM for Project: $PROJECT_ID"
echo "Granting permissions to service account: $DEFAULT_SA"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA}" \
    --role="roles/pubsub.publisher"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA}" \
    --role="roles/pubsub.subscriber"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA}" \
    --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA}" \
    --role="roles/bigquery.dataViewer"

echo "IAM configuration complete! Your agents are authorized."

# Set up SMS notification
#echo -n "ACa3f54cb26762970ec5402a1ab4f09234" | gcloud secrets create twilio-sid --data-file=-
#echo -n "5c3a15ef5f3380bbbe337eda73b56c7e" | gcloud secrets create twilio-token --data-file=-
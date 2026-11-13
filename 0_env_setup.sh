#!/bin/bash
set -euo pipefail

PROJECT_ID=$(gcloud config get-value core/project --quiet 2>/dev/null | tail -n 1 || true)
if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
    PROJECT_ID="qwiklabs-gcp-04-486b161c6a8e"
    gcloud config set project "$PROJECT_ID" --quiet >/dev/null 2>&1 || true
fi
export PROJECT_ID
export DEVSHELL_PROJECT_ID="$PROJECT_ID"
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' --quiet 2>/dev/null | tail -n 1 || echo "211493516642")
export DEFAULT_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
if [ -t 0 ] && [ -z "${location:-}" ]; then
    read -p 'Enter your project location [default: us-central1]: ' location
fi
export location="${location:-us-central1}"
export REGION="$location"

echo -e "\nYour project credentials:"
echo "export PROJECT_ID=$PROJECT_ID" | tee -a ~/.bashrc
echo "export DEVSHELL_PROJECT_ID=$PROJECT_ID" | tee -a ~/.bashrc
echo "export GOOGLE_CLOUD_PROJECT=$PROJECT_ID" | tee -a ~/.bashrc
echo "export PROJECT_NUMBER=$PROJECT_NUMBER" | tee -a ~/.bashrc
echo "export DEFAULT_SA=$DEFAULT_SA" | tee -a ~/.bashrc
echo "export location=$location" | tee -a ~/.bashrc
echo "export REGION=$REGION" | tee -a ~/.bashrc

gcloud services enable \
    aiplatform.googleapis.com \
    bigquery.googleapis.com \
    pubsub.googleapis.com \
    run.googleapis.com \
    secretmanager.googleapis.com \
    artifactregistry.googleapis.com \
    --project="$PROJECT_ID" --quiet 2>/dev/null || echo "Note: Service enablement skipped (APIs are managed by Qwiklabs environment)."

python3 -m venv .venv
source .venv/bin/activate

pip install --upgrade pip -q
pip install --upgrade -r requirements.txt -q
echo "Python dependencies installed in .venv successfully!"

export PATH=$PATH:~/.local/bin

echo "Configuring IAM for Project: $PROJECT_ID"
for ROLE in roles/pubsub.publisher roles/pubsub.subscriber roles/bigquery.jobUser roles/bigquery.dataViewer; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${DEFAULT_SA}" \
        --role="$ROLE" --quiet >/dev/null 2>&1 || true
done

echo "Environment setup complete!"

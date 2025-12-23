#!/bin/bash
PROJECT_ID=$(gcloud config get-value project)
POOL_NAME="gh-pool-v1"
PROVIDER_NAME="gh-provider-test"

echo "Testing provider creation with minimal mapping..."
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
    --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" \
    --attribute-mapping="google.subject=assertion.sub" \
    --issuer-uri="https://token.actions.githubusercontent.com"

if [ $? -eq 0 ]; then
    echo "✅ Minimal provider created."
    gcloud iam workload-identity-pools providers delete "$PROVIDER_NAME" --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" --quiet
else
    echo "❌ Minimal provider creation failed."
fi

echo "Testing provider creation with repo mapping..."
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
    --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --issuer-uri="https://token.actions.githubusercontent.com"

if [ $? -eq 0 ]; then
    echo "✅ Repo mapping provider created."
    gcloud iam workload-identity-pools providers delete "$PROVIDER_NAME" --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" --quiet
else
    echo "❌ Repo mapping provider creation failed."
fi

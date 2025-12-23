#!/bin/bash

# 1. Validation
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <PROJECT_ID> <SERVICE_ACCOUNT_EMAIL> <POOL_NAME> <PROVIDER_NAME> <GITHUB_REPO>"
    exit 1
fi

PROJECT_ID=$1
SERVICE_ACCOUNT=$2
POOL_NAME=$3
PROVIDER_NAME=$4
REPO=$5

# Get Project Number (needed for IAM binding string)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

echo "Checking configuration for Project: $PROJECT_ID ($PROJECT_NUMBER)..."

# 2. Check/Create Workload Identity Pool
if gcloud iam workload-identity-pools describe "$POOL_NAME" --project="$PROJECT_ID" --location="global" &>/dev/null; then
    echo "✅ Pool '$POOL_NAME' already exists. Skipping creation."
else
    echo "🏗️ Creating Pool '$POOL_NAME'..."
    gcloud iam workload-identity-pools create "$POOL_NAME" \
        --project="$PROJECT_ID" --location="global" --display-name="GitHub Actions Pool"
fi

# 3. Check/Create Workload Identity Provider
if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
    --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" &>/dev/null; then
    echo "✅ Provider '$PROVIDER_NAME' already exists. Skipping creation."
else
    echo "🏗️ Creating Provider '$PROVIDER_NAME'..."
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
        --project="$PROJECT_ID" \
        --location="global" \
        --workload-identity-pool="$POOL_NAME" \
        --display-name="GitHub Actions Provider" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
        --issuer-uri="https://token.actions.githubusercontent.com"
fi

# 4. Add IAM Policy Binding for the specific REPO
# Note: 'add-iam-policy-binding' is inherently safe; it adds the member if it doesn't exist.
echo "🔗 Binding Repository '$REPO' to Service Account..."
gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_NAME/attribute.repository/$REPO"

# 5. Output the Provider Name for your GitHub YAML
echo "--------------------------------------------------------"
echo "Configuration complete for repo: $REPO"
echo "Use this value for 'workload_identity_provider' in GitHub Actions:"
gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
    --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" --format="value(name)"

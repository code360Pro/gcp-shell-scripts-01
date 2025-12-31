#!/bin/bash

# 1. Validation & Variables
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <PROJECT_ID> <SERVICE_ACCOUNT_NAME> <POOL_NAME> <PROVIDER_NAME> <GITHUB_REPO> <LOCATION>"
    echo "Example: $0 my-prj sa gh-pool gh-provider org/repo us-central1"
    exit 1
fi

PROJECT_ID=$1
SA_NAME=$2
POOL_NAME=$3
PROVIDER_NAME=$4
REPO=$5
LOCATION=$6
REPO_NAME=$(echo $REPO | cut -d'/' -f2) # Extracts 'repo' from 'org/repo'

SERVICE_ACCOUNT="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

echo "--------------------------------------------------------"
echo "Starting Idempotent Setup for $REPO"
echo "--------------------------------------------------------"

# 2. Check/Create Service Account
if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" --project="$PROJECT_ID" &>/dev/null; then
    echo "✅ Service Account '$SA_NAME' already exists."
else
    echo "🏗️ Creating Service Account '$SA_NAME'..."
    gcloud iam service-accounts create "$SA_NAME" \
        --project="$PROJECT_ID" \
        --display-name="CI/CD Build and Deploy Service Account"
fi

# 3. Check/Create Workload Identity Pool
if gcloud iam workload-identity-pools describe "$POOL_NAME" --project="$PROJECT_ID" --location="global" &>/dev/null; then
    echo "✅ Pool '$POOL_NAME' already exists."
else
    echo "🏗️ Creating Pool '$POOL_NAME'..."
    gcloud iam workload-identity-pools create "$POOL_NAME" --project="$PROJECT_ID" --location="global"
fi

# . Check/Create Workload Identity Provider
if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" &>/dev/null; then
    echo "✅ Provider '$PROVIDER_NAME' already exists."
else
    echo "🏗️ Creating Provider '$PROVIDER_NAME'..."
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
        --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" \
        --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
        --attribute-condition="assertion.sub != ''" \
        --issuer-uri="https://token.actions.githubusercontent.com"
fi

# 5. Bind GitHub Repo to Service Account
echo "🔗 Binding GitHub Repo to Service Account..."
gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_NAME/attribute.repository/$REPO"

# 6. Check/Create Artifact Registry Repository
if gcloud artifacts repositories describe "$REPO_NAME" --project="$PROJECT_ID" --location="$LOCATION" &>/dev/null; then
    echo "✅ Artifact Registry '$REPO_NAME' already exists."
else
    echo "🏗️ Creating Artifact Registry '$REPO_NAME'..."
    gcloud artifacts repositories create "$REPO_NAME" \
        --project="$PROJECT_ID" --location="$LOCATION" --repository-format=docker
fi

# 7. Grant Push Permission to Service Account
echo "🔐 Granting Artifact Registry Writer role to Service Account..."
gcloud artifacts repositories add-iam-policy-binding "$REPO_NAME" \
    --project="$PROJECT_ID" --location="$LOCATION" \
    --role="roles/artifactregistry.writer" \
    --member="serviceAccount:$SERVICE_ACCOUNT"

# 8 Allow the SA to see the cluster metadata (needed for get-credentials)
echo "🔐 Granting container.clusterViewer role to Service Account..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/container.clusterViewer" \
    --condition=None --quiet

#9 Allow the SA to actually deploy/edit resources in the cluster
echo "🔐 Granting container.developer role to Service Account..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/container.admin" \
    --condition=None --quiet   

echo "--------------------------------------------------------"
echo "ALL SET! Copy this Provider Name for your GitHub YAML:"
gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
    --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" --format="value(name)"

#!/bin/bash
# ----------------------------------------------------------------------------
# Script to set up GCP resources for Terraform deployment via GitHub Actions
# using Workload Identity Federation (WIF). All required variables are passed
# as command-line arguments.
# ----------------------------------------------------------------------------

# --- PARAMETER CHECK ---
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <PROJECT_ID> <REPO_OWNER> <REPO_NAME> <GCS_REGION>"
    echo "Example: $0 my-project my-company terraform-vm-deploy us-central1"
    exit 1
fi

# --- PARAMETER ASSIGNMENT ---
PROJECT_ID=$1
REPO_OWNER=$2          # Your GitHub Organization or Username
REPO_NAME=$3           # Your GitHub Repository Name
LOCATION=$4            # Region for the GCS Bucket (e.g., us-central1)

# --- FIXED / DERIVED VARIABLES ---
SA_NAME="github-tf-deployer"                
BUCKET_NAME="${PROJECT_ID}-tfstate-bucket"  # GCS Bucket name derived from Project ID
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
WIF_POOL_ID="github-actions-pool"
WIF_PROVIDER_ID="github-provider"

# Set the current project context
echo "Setting gcloud project to: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

# --- 1. ENABLE NECESSARY APIS ---
echo "--- 1. Enabling necessary APIs..."
gcloud services enable \
    compute.googleapis.com \
    iam.googleapis.com \
    storage-api.googleapis.com \
    serviceusage.googleapis.com \
    --project="${PROJECT_ID}" || { echo "Failed to enable APIs."; exit 1; }
echo "APIs enabled successfully."

# --- 2. CREATE SERVICE ACCOUNT ---
echo "--- 2. Creating Service Account: ${SA_NAME}"
gcloud iam service-accounts create "${SA_NAME}" \
    --description="Terraform deployer via GitHub Actions using WIF." \
    --display-name="GitHub Terraform Deployer SA"

# --- 3. CREATE TERRAFORM STATE BUCKET ---
echo "--- 3. Creating GCS bucket for Terraform state: ${BUCKET_NAME} in ${LOCATION}"
gsutil mb -l "${LOCATION}" "gs://${BUCKET_NAME}"
gsutil versioning set on "gs://${BUCKET_NAME}"

# --- 4. GRANT PERMISSIONS TO SERVICE ACCOUNT (ON PROJECT & BUCKET) ---
echo "--- 4. Granting IAM Roles to Service Account: ${SA_EMAIL}"

# 4.1. Roles for VM Deployment (Project Level)
echo "   - Granting Compute Instance Admin (v1) for VM deployment..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.instanceAdmin.v1" \
    --condition=None

echo "   - Granting Service Account User for potential VM identity..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None 

# 4.2. Role for Terraform State Management (Bucket Level)
echo "   - Granting Storage Object Admin for Terraform state bucket..."
gsutil iam ch "serviceAccount:${SA_EMAIL}:objectAdmin" "gs://${BUCKET_NAME}"

echo "Service Account permissions granted successfully."

# --- 5. SETUP WORKLOAD IDENTITY FEDERATION (WIF) ---

# 5.1. Create Workload Identity Pool
echo "--- 5. Setting up WIF: Creating Workload Identity Pool: ${WIF_POOL_ID}"
gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
    --location="global" \
    --display-name="GitHub Actions Workload Identity Pool"

# Get Project Number for the full WIF provider path
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
WIF_POOL_PATH="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}"

# 5.2. Create OIDC Provider for GitHub
echo "   - Creating Workload Identity Provider for GitHub OIDC: ${WIF_PROVIDER_ID}"
gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
    --location="global" \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --display-name="GitHub OIDC Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --project="${PROJECT_ID}"

# 5.3. Grant Workload Identity User Role (The trust relationship)
# This allows the GitHub principal (the repository) to impersonate the SA.
GITHUB_PRINCIPAL="principalSet://iam.googleapis.com/${WIF_POOL_PATH}/attribute.repository/${REPO_OWNER}/${REPO_NAME}"

echo "   - Binding Workload Identity User Role to SA for GitHub principal: ${GITHUB_PRINCIPAL}"
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${GITHUB_PRINCIPAL}"

# --- 6. OUTPUT CONFIGURATION FOR GITHUB ACTIONS ---

WIF_PROVIDER_FULL_PATH="${WIF_POOL_PATH}/providers/${WIF_PROVIDER_ID}"

echo "------------------------------------------------------------------"
echo "✅ SETUP COMPLETE! Use the following values in your GitHub Secrets"
echo "------------------------------------------------------------------"
echo "GCP_SERVICE_ACCOUNT_EMAIL: ${SA_EMAIL}"
echo "GCP_WORKLOAD_IDENTITY_PROVIDER: ${WIF_PROVIDER_FULL_PATH}"
echo "TERRAFORM_STATE_BUCKET: ${BUCKET_NAME}"
echo "------------------------------------------------------------------"

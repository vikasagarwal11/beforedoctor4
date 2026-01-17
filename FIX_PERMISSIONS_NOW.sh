#!/bin/bash
# Quick fix for Cloud Build permissions

PROJECT_ID="gen-lang-client-0337309484"
PROJECT_NUMBER="531178459822"
COMPUTE_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "🔧 Fixing Cloud Build permissions..."
echo "   Service Account: $COMPUTE_SERVICE_ACCOUNT"
echo ""

# Grant Cloud Build Service Account role
echo "1️⃣  Granting Cloud Build permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SERVICE_ACCOUNT}" \
  --role="roles/cloudbuild.builds.builder" \
  --condition=None

# Grant Service Account User role
echo "2️⃣  Granting Service Account User permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SERVICE_ACCOUNT}" \
  --role="roles/iam.serviceAccountUser" \
  --condition=None

# Grant Storage Admin for Cloud Build
echo "3️⃣  Granting Storage Admin permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SERVICE_ACCOUNT}" \
  --role="roles/storage.admin" \
  --condition=None

echo ""
echo "✅ Permissions granted!"
echo "   Now run: ./DEPLOY_PRODUCTION.sh"

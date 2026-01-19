#!/bin/bash
# Complete Cloud Run Deployment Script for BeforeDoctor Gateway

set -e  # Exit on error

echo "🚀 BeforeDoctor Gateway - Cloud Run Deployment"
echo "=============================================="
echo ""

# Configuration
PROJECT_ID="gen-lang-client-0337309484"
SERVICE_NAME="beforedoctor-gateway"
REGION="us-central1"
SERVICE_ACCOUNT="bd-gateway-svc@gen-lang-client-0337309484.iam.gserviceaccount.com"

echo "📋 Configuration:"
echo "   Project: $PROJECT_ID"
echo "   Service: $SERVICE_NAME"
echo "   Region: $REGION"
echo "   Service Account: $SERVICE_ACCOUNT"
echo ""

# Step 1: Enable required APIs
echo "1️⃣  Enabling required APIs..."
gcloud services enable \
  aiplatform.googleapis.com \
  secretmanager.googleapis.com \
  run.googleapis.com \
  --project=$PROJECT_ID

echo "   ✅ APIs enabled"
echo ""

# Step 2: Service Account Configuration
echo "2️⃣  Configuring Service Account..."
echo "   Using Application Default Credentials (ADC)"
echo "   No API keys needed - OAuth2 bearer tokens used automatically"
echo "   ✅ Service account configured"
echo ""

# Step 3: Grant service account Vertex AI access (if not already done)
echo "3️⃣  Verifying service account permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/aiplatform.user" \
  --condition=None 2>/dev/null || echo "   ✅ Permissions already set"

echo ""

# Step 4: Deploy to Cloud Run
echo "4️⃣  Deploying to Cloud Run..."
gcloud run deploy $SERVICE_NAME \
  --source . \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --service-account=$SERVICE_ACCOUNT \
  --set-env-vars="VERTEX_AI_PROJECT_ID=$PROJECT_ID,VERTEX_AI_LOCATION=$REGION,NODE_ENV=production" \
  --memory=512Mi \
  --cpu=1 \
  --timeout=3600 \
  --max-instances=10 \
  --project=$PROJECT_ID

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📱 Next steps:"
echo "   1. Get your gateway URL:"
echo "      gcloud run services describe $SERVICE_NAME --region=$REGION --project=$PROJECT_ID --format='value(status.url)'"
echo ""
echo "   2. Update Flutter app with the gateway URL"
echo "   3. Test the connection"


#!/bin/bash
# Complete Production Deployment Script for BeforeDoctor Gateway
# This script handles everything needed for Cloud Run deployment

set -e  # Exit on error

echo "🚀 BeforeDoctor Gateway - Production Deployment"
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

# Step 1: Check gcloud installation
echo "1️⃣  Checking Google Cloud CLI..."
if ! command -v gcloud &> /dev/null; then
    echo "   ❌ gcloud CLI not found. Installing..."
    brew install google-cloud-sdk
    echo "   ✅ gcloud CLI installed"
else
    echo "   ✅ gcloud CLI found: $(gcloud --version | head -1)"
fi
echo ""

# Step 2: Authenticate with Google Cloud
echo "2️⃣  Authenticating with Google Cloud..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "   Please authenticate with Google Cloud..."
    gcloud auth login
else
    echo "   ✅ Already authenticated: $(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
fi

# Set project
gcloud config set project $PROJECT_ID
echo "   ✅ Project set to: $PROJECT_ID"
echo ""

# Step 3: Enable required APIs
echo "3️⃣  Enabling required APIs..."
gcloud services enable \
  aiplatform.googleapis.com \
  secretmanager.googleapis.com \
  run.googleapis.com \
  --project=$PROJECT_ID

echo "   ✅ APIs enabled"
echo ""

# Step 4: Create Service Account (if it doesn't exist)
echo "4️⃣  Setting up Service Account..."
if ! gcloud iam service-accounts describe $SERVICE_ACCOUNT --project=$PROJECT_ID &>/dev/null; then
    echo "   Creating service account..."
    gcloud iam service-accounts create bd-gateway-svc \
      --display-name="BeforeDoctor Gateway Service Account" \
      --project=$PROJECT_ID
    echo "   ✅ Service account created"
else
    echo "   ✅ Service account already exists"
fi

# Grant Vertex AI access
echo "   Granting Vertex AI permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/aiplatform.user" \
  --condition=None 2>/dev/null || echo "   ✅ Permissions already set"

# Step 4b: Grant Cloud Build permissions to default compute service account
echo "   Granting Cloud Build permissions to default compute service account..."
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
COMPUTE_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Grant Cloud Build Service Account role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SERVICE_ACCOUNT}" \
  --role="roles/cloudbuild.builds.builder" \
  --condition=None 2>/dev/null || echo "   ✅ Cloud Build permissions already set"

# Grant Service Account User role (needed to use the service account)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SERVICE_ACCOUNT}" \
  --role="roles/iam.serviceAccountUser" \
  --condition=None 2>/dev/null || echo "   ✅ Service Account User permissions already set"

# Grant Storage Admin for Cloud Build (needed to access source archives)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SERVICE_ACCOUNT}" \
  --role="roles/storage.admin" \
  --condition=None 2>/dev/null || echo "   ✅ Storage Admin permissions already set"

echo ""

# Step 5: Navigate to gateway directory
echo "5️⃣  Preparing gateway for deployment..."
cd "$(dirname "$0")/gateway"

if [ ! -f "package.json" ]; then
    echo "   ❌ Error: package.json not found. Are you in the right directory?"
    exit 1
fi

echo "   ✅ Gateway directory found"
echo ""

# Step 6: Deploy to Cloud Run
echo "6️⃣  Deploying to Cloud Run..."
echo "   This may take a few minutes..."
echo ""

gcloud run deploy $SERVICE_NAME \
  --source . \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --service-account=$SERVICE_ACCOUNT \
  --set-env-vars="VERTEX_AI_PROJECT_ID=$PROJECT_ID,VERTEX_AI_LOCATION=$REGION,NODE_ENV=production,ALLOW_MOCK_TOKENS=true" \
  --memory=512Mi \
  --cpu=1 \
  --timeout=3600 \
  --max-instances=10 \
  --project=$PROJECT_ID

echo ""
echo "✅ Deployment complete!"
echo ""

# Step 7: Get production URL
echo "7️⃣  Getting production gateway URL..."
GATEWAY_URL=$(gcloud run services describe $SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format='value(status.url)')

if [ -n "$GATEWAY_URL" ]; then
    # Convert HTTPS URL to WSS (WebSocket Secure)
    WSS_URL="${GATEWAY_URL/https:\/\//wss:\/\/}"
    echo "   ✅ Gateway URL: $GATEWAY_URL"
    echo "   ✅ WebSocket URL: $WSS_URL"
    echo ""
    
    # Step 8: Update Flutter app configuration
    echo "8️⃣  Next Steps:"
    echo ""
    echo "   📱 Update Flutter app with production URL:"
    echo "      Edit: lib/app/app_shell.dart"
    echo ""
    echo "      Change:"
    echo "        final gatewayUrl = Platform.isAndroid"
    echo "            ? 'ws://10.0.2.2:8080'"
    echo "            : 'ws://192.168.5.10:8080';"
    echo ""
    echo "      To:"
    echo "        final gatewayUrl = '${WSS_URL}';"
    echo ""
    echo "   ✅ Production URL: ${WSS_URL}"
    echo ""
    echo "   📝 Note: Use 'wss://' (secure WebSocket) for production, not 'ws://'"
    echo ""
else
    echo "   ⚠️  Could not retrieve gateway URL. Run manually:"
    echo "      gcloud run services describe $SERVICE_NAME --region=$REGION --format='value(status.url)'"
fi

echo ""
echo "🎉 Production deployment complete!"
echo ""

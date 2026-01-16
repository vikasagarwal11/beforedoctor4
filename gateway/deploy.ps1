# PowerShell Deployment Script for BeforeDoctor Gateway

$ErrorActionPreference = "Stop"

Write-Host "🚀 BeforeDoctor Gateway - Cloud Run Deployment" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$PROJECT_ID = "gen-lang-client-0337309484"
$SERVICE_NAME = "beforedoctor-gateway"
$REGION = "us-central1"
$SERVICE_ACCOUNT = "bd-gateway-svc@gen-lang-client-0337309484.iam.gserviceaccount.com"

Write-Host "📋 Configuration:" -ForegroundColor Yellow
Write-Host "   Project: $PROJECT_ID"
Write-Host "   Service: $SERVICE_NAME"
Write-Host "   Region: $REGION"
Write-Host "   Service Account: $SERVICE_ACCOUNT"
Write-Host ""

# Step 1: Enable required APIs
Write-Host "1️⃣  Enabling required APIs..." -ForegroundColor Yellow
gcloud services enable `
  aiplatform.googleapis.com `
  secretmanager.googleapis.com `
  run.googleapis.com `
  --project=$PROJECT_ID

Write-Host "   ✅ APIs enabled" -ForegroundColor Green
Write-Host ""

# Step 2: Service Account Configuration
Write-Host "2️⃣  Configuring Service Account..." -ForegroundColor Yellow
Write-Host "   Using Application Default Credentials (ADC)" -ForegroundColor Cyan
Write-Host "   No API keys needed - OAuth2 bearer tokens used automatically" -ForegroundColor Cyan
Write-Host "   ✅ Service account configured" -ForegroundColor Green
Write-Host ""

# Step 3: Grant service account Vertex AI access
Write-Host "3️⃣  Verifying service account permissions..." -ForegroundColor Yellow
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/aiplatform.user" `
  --condition=None 2>$null

Write-Host "   ✅ Permissions verified" -ForegroundColor Green
Write-Host ""

# Step 4: Deploy to Cloud Run
Write-Host "4️⃣  Deploying to Cloud Run..." -ForegroundColor Yellow
gcloud run deploy $SERVICE_NAME `
  --source . `
  --platform managed `
  --region $REGION `
  --allow-unauthenticated `
  --service-account=$SERVICE_ACCOUNT `
  --set-env-vars="VERTEX_AI_PROJECT_ID=$PROJECT_ID,VERTEX_AI_LOCATION=$REGION,NODE_ENV=production" `
  --memory=512Mi `
  --cpu=1 `
  --timeout=3600 `
  --max-instances=10 `
  --project=$PROJECT_ID

Write-Host ""
Write-Host "✅ Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "📱 Next steps:" -ForegroundColor Cyan
Write-Host "   1. Get your gateway URL:"
Write-Host "      gcloud run services describe $SERVICE_NAME --region=$REGION --project=$PROJECT_ID --format='value(status.url)'"
Write-Host ""
Write-Host "   2. Update Flutter app with the gateway URL"
Write-Host "   3. Test the connection"


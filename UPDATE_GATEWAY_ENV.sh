#!/bin/bash
# Quick fix: Update gateway environment variable to allow mock tokens

echo "🔧 Updating gateway to allow mock tokens..."

gcloud run services update beforedoctor-gateway \
  --region=us-central1 \
  --update-env-vars="ALLOW_MOCK_TOKENS=true" \
  --project=gen-lang-client-0337309484

echo ""
echo "✅ Gateway updated! Wait a few seconds, then test the app again."

#!/bin/bash

# Deploy Supabase Schema Script
# This applies the conversation system schema to Supabase

echo "🔧 Deploying Supabase Schema..."
echo ""

# Check if supabase is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found. Install it with:"
    echo "   npm install -g supabase"
    exit 1
fi

# Check if .env.local exists
if [ ! -f ".env.local" ]; then
    echo "⚠️  .env.local not found. Create it with your Supabase credentials:"
    echo "   SUPABASE_URL=https://scrksfxnkxmvvdzwmqnc.supabase.co"
    echo "   SUPABASE_ANON_KEY=<your-anon-key>"
    echo "   SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>"
fi

echo "📝 Running migration: supabase/migrations/0006_conversation_system.sql"
echo ""

# Method 1: Using supabase DB push (if you have a local Supabase setup)
# supabase db push

# Method 2: Manual application via Supabase Dashboard
echo "✅ To apply the schema manually:"
echo "   1. Go to https://supabase.com/dashboard"
echo "   2. Select your project (scrksfxnkxmvvdzwmqnc)"
echo "   3. Click 'SQL Editor'"
echo "   4. Click 'New Query'"
echo "   5. Copy & paste contents of: supabase/migrations/0006_conversation_system.sql"
echo "   6. Click 'Run'"
echo ""
echo "✅ To apply via CLI:"
echo "   supabase db push --db-url postgresql://postgres:your-password@db.scrksfxnkxmvvdzwmqnc.supabase.co:5432/postgres"
echo ""

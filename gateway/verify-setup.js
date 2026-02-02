// Setup Verification Script
// Checks if everything is configured correctly

import { existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { config } from './config.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

console.log('🔍 Verifying gateway setup...\n');

let allGood = true;

// Check Node.js version
const nodeVersion = process.version;
const majorVersion = parseInt(nodeVersion.slice(1).split('.')[0]);
if (majorVersion < 18) {
  console.error('❌ Node.js version must be 18 or higher');
  console.error(`   Current: ${nodeVersion}`);
  allGood = false;
} else {
  console.log(`✅ Node.js version: ${nodeVersion}`);
}

// Check .env file
const envPath = join(__dirname, '.env');
if (!existsSync(envPath)) {
  console.warn('⚠️  .env file not found');
  console.warn('   Create it from .env.example');
  allGood = false;
} else {
  console.log('✅ .env file exists');
}

// Check required environment variables
console.log('\n📋 Configuration:');
console.log('   Vertex AI Auth: ADC (service account / default credentials)');
console.log(`   VERTEX_AI_PROJECT_ID: ${config.vertexAI.projectId || 'Using default'}`);
console.log(`   VERTEX_AI_LOCATION: ${config.vertexAI.location}`);
console.log(`   PORT: ${config.server.port}`);
console.log(`   NODE_ENV: ${config.server.nodeEnv}`);

// Check dependencies
console.log('\n📦 Checking dependencies...');
try {
  await import('ws');
  console.log('✅ ws (WebSocket)');
} catch (e) {
  console.error('❌ ws package not found');
  console.error('   Run: npm install');
  allGood = false;
}

try {
  await import('dotenv');
  console.log('✅ dotenv');
} catch (e) {
  console.error('❌ dotenv package not found');
  allGood = false;
}

try {
  await import('@google-cloud/vertexai');
  console.log('✅ @google-cloud/vertexai');
} catch (e) {
  console.error('❌ @google-cloud/vertexai package not found');
  allGood = false;
}

try {
  await import('@supabase/supabase-js');
  console.log('✅ @supabase/supabase-js');
} catch (e) {
  console.error('❌ @supabase/supabase-js package not found');
  allGood = false;
}

// Summary
console.log('\n' + '='.repeat(50));
if (allGood) {
  console.log('✅ Setup looks good! You can start the server with:');
  console.log('   npm start');
} else {
  console.log('❌ Some issues found. Please fix them before starting the server.');
  process.exit(1);
}
console.log('='.repeat(50));



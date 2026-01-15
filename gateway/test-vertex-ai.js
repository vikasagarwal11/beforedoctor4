// Test script to verify Vertex AI connection with service account
import { VertexAI } from '@google-cloud/vertexai';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { config } from './config.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function testVertexAI() {
  console.log('🧪 Testing Vertex AI connection...\n');

  try {
    // Load service account if available
    let credentials = null;
    if (config.firebase.serviceAccountPath) {
      try {
        const serviceAccountPath = config.firebase.serviceAccountPath.startsWith('./')
            ? join(__dirname, config.firebase.serviceAccountPath.replace('./', ''))
            : config.firebase.serviceAccountPath;
        const serviceAccountJson = readFileSync(serviceAccountPath, 'utf8');
        credentials = JSON.parse(serviceAccountJson);
        console.log('✅ Service account loaded:', credentials.client_email);
      } catch (e) {
        console.warn('⚠️  Could not load service account:', e.message);
        console.log('   Will use default credentials (Application Default Credentials)');
      }
    }

    // Initialize Vertex AI
    const vertexAI = new VertexAI({
      project: config.vertexAI.projectId,
      location: config.vertexAI.location,
      ...(credentials && {
        googleAuthOptions: {
          credentials: credentials,
        }
      }),
    });

    console.log(`✅ Vertex AI client initialized`);
    console.log(`   Project: ${config.vertexAI.projectId}`);
    console.log(`   Location: ${config.vertexAI.location}\n`);

    // Test with a simple model (not the live audio one, just to verify connection)
    // Try different model names that are commonly available
    let model;
    const modelNames = ['gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-pro'];
    
    for (const modelName of modelNames) {
      try {
        console.log(`   Trying model: ${modelName}...`);
        model = vertexAI.getGenerativeModel({
          model: modelName,
        });
        console.log(`   ✅ Using model: ${modelName}`);
        break;
      } catch (e) {
        if (modelNames.indexOf(modelName) === modelNames.length - 1) {
          // Last model failed, throw error
          throw new Error(`None of the test models are available. This might mean:\n   1. Vertex AI API is not enabled\n   2. Project doesn't have access to Gemini models\n   3. Wait a few minutes for IAM changes to propagate\n\nOriginal error: ${e.message}`);
        }
        continue;
      }
    }

    console.log('🧪 Testing model access...');
    const result = await model.generateContent('Say "Hello, Vertex AI connection successful!" in one sentence.');
    const response = result.response;
    const text = response.text();

    console.log('✅ Model response received:');
    console.log(`   "${text}"\n`);
    console.log('🎉 Vertex AI connection test PASSED!');
    console.log('\n✅ Your service account has the correct permissions.');
    console.log('✅ Gateway server is ready to use Vertex AI.');

  } catch (error) {
    console.error('\n❌ Vertex AI connection test FAILED:');
    console.error(`   Error: ${error.message}\n`);
    
    if (error.message.includes('permission') || error.message.includes('IAM')) {
      console.error('⚠️  Permission Issue Detected:');
      console.error('   1. Verify service account has "Vertex AI User" role');
      console.error('   2. Check that the role is assigned in the correct project');
      console.error('   3. Wait a few minutes for IAM changes to propagate\n');
    } else {
      console.error('   Full error:', error);
    }
    
    process.exit(1);
  }
}

testVertexAI();


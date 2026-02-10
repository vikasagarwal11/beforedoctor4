// Supabase Audio Storage Service
// Production-grade: Handles audio file uploads and downloads from Supabase Storage
// Replaces Firebase Storage functionality

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class SupabaseAudioService {
  final SupabaseClient _client = supabase;
  final String _bucketName = SupabaseConfig.audioStorageBucket;

  /// Upload audio file to Supabase Storage
  /// Returns the public URL of the uploaded file
  ///
  /// [userId] - User ID for organizing files
  /// [conversationId] - Conversation ID for associating audio
  /// [audioData] - Raw audio data bytes
  /// [fileName] - Name of the file (e.g., 'user_audio_123.pcm')
  /// [contentType] - MIME type (default: 'audio/pcm')
  Future<String> uploadAudio({
    required String userId,
    required String conversationId,
    required Uint8List audioData,
    required String fileName,
    String contentType = 'audio/pcm',
  }) async {
    try {
      // File path: userId/conversationId/fileName
      // This structure allows RLS policies to work correctly
      final filePath = '$userId/$conversationId/$fileName';

      // Upload file to Supabase Storage
      await _client.storage.from(_bucketName).uploadBinary(
            filePath,
            audioData,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: false, // Don't overwrite existing files
            ),
          );

      // Get public URL (or signed URL for private buckets)
      final publicUrl =
          _client.storage.from(_bucketName).getPublicUrl(filePath);

      print('✅ Audio uploaded successfully: $filePath');
      return publicUrl;
    } catch (e) {
      print('❌ Failed to upload audio: $e');
      rethrow;
    }
  }

  /// Download audio file from Supabase Storage
  /// Returns the audio data as bytes
  ///
  /// [filePath] - Full path to the file in storage
  Future<Uint8List> downloadAudio(String filePath) async {
    try {
      final data = await _client.storage.from(_bucketName).download(filePath);
      print('✅ Audio downloaded successfully: $filePath');
      return data;
    } catch (e) {
      print('❌ Failed to download audio: $e');
      rethrow;
    }
  }

  /// Get signed URL for private audio file (valid for 1 hour)
  /// Use this when the bucket is private
  ///
  /// [filePath] - Full path to the file in storage
  /// [expiresIn] - Seconds until URL expires (default: 3600 = 1 hour)
  Future<String> getSignedUrl(
    String filePath, {
    int expiresIn = 3600,
  }) async {
    try {
      final signedUrl = await _client.storage.from(_bucketName).createSignedUrl(
            filePath,
            expiresIn,
          );
      return signedUrl;
    } catch (e) {
      print('❌ Failed to get signed URL: $e');
      rethrow;
    }
  }

  /// Delete audio file from Supabase Storage
  ///
  /// [filePath] - Full path to the file in storage
  Future<void> deleteAudio(String filePath) async {
    try {
      await _client.storage.from(_bucketName).remove([filePath]);
      print('✅ Audio deleted successfully: $filePath');
    } catch (e) {
      print('❌ Failed to delete audio: $e');
      rethrow;
    }
  }

  /// List all audio files for a user in a conversation
  ///
  /// [userId] - User ID
  /// [conversationId] - Conversation ID
  Future<List<FileObject>> listAudioFiles(
    String userId,
    String conversationId,
  ) async {
    try {
      final files = await _client.storage
          .from(_bucketName)
          .list(path: '$userId/$conversationId');
      return files;
    } catch (e) {
      print('❌ Failed to list audio files: $e');
      rethrow;
    }
  }
}

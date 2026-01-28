import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:logger/logger.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 110,
      colors: false,
      printTime: true,
    ),
  );

  void debug(String message, {Map<String, Object?>? data}) {
    _logger.d(_formatMessage(message, data));
    _logAnalytics(level: 'debug', message: message, data: data);
  }

  void info(String message, {Map<String, Object?>? data}) {
    _logger.i(_formatMessage(message, data));
    _logAnalytics(level: 'info', message: message, data: data);
  }

  void warn(String message, {Map<String, Object?>? data}) {
    _logger.w(_formatMessage(message, data));
    _logAnalytics(level: 'warn', message: message, data: data);
  }

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    _logger.e(message,
        error: error ?? _formatData(data), stackTrace: stackTrace);
    _logAnalytics(level: 'error', message: message, data: data);
    _logCrashlytics(
        message: message, error: error, stackTrace: stackTrace, data: data);
  }

  void _logAnalytics({
    required String level,
    required String message,
    Map<String, Object?>? data,
  }) {
    if (Firebase.apps.isEmpty) return;
    final sanitized = _sanitizeParams(data);
    final params = <String, Object>{
      'level': level,
      'message': message,
      ...sanitized.map((key, value) => MapEntry(key, value ?? '')),
    };
    unawaited(FirebaseAnalytics.instance
        .logEvent(name: 'app_log', parameters: params));
  }

  void _logCrashlytics({
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    if (Firebase.apps.isEmpty) return;
    unawaited(
        FirebaseCrashlytics.instance.log('[$message] ${_formatData(data)}'));
    if (error != null || stackTrace != null) {
      final infoList = data == null ? <Object>[] : <Object>[data];
      unawaited(FirebaseCrashlytics.instance.recordError(
        error ?? message,
        stackTrace ?? StackTrace.current,
        reason: message,
        information: infoList,
      ));
    }
  }

  Map<String, Object?> _sanitizeParams(Map<String, Object?>? data) {
    if (data == null) return const <String, Object?>{};
    final sanitized = <String, Object?>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value == null) continue;
      // Firebase Analytics only accepts String or num (not bool)
      if (value is num || value is String) {
        sanitized[entry.key] = value;
      } else if (value is bool) {
        // Convert bool to String for Firebase Analytics compatibility
        sanitized[entry.key] = value.toString();
      } else {
        sanitized[entry.key] = value.toString();
      }
    }
    return sanitized;
  }

  String _formatData(Map<String, Object?>? data) {
    if (data == null || data.isEmpty) return '';
    return data.entries.map((e) => '${e.key}=${e.value}').join(' ');
  }

  String _formatMessage(String message, Map<String, Object?>? data) {
    final formatted = _formatData(data);
    if (formatted.isEmpty) return message;
    return '$message | $formatted';
  }
}

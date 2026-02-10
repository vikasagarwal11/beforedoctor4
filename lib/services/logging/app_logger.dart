import 'package:logger/logger.dart';

// Removed Firebase Analytics and Crashlytics - using Supabase instead

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
  }

  void info(String message, {Map<String, Object?>? data}) {
    _logger.i(_formatMessage(message, data));
  }

  void warn(String message, {Map<String, Object?>? data}) {
    _logger.w(_formatMessage(message, data));
  }

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    _logger.e(message,
        error: error ?? _formatData(data), stackTrace: stackTrace);
  }

  static void recordError(String message, {Map<String, dynamic>? data}) {
    instance.error(message, error: data);
  }

  static void recordException(Object exception, StackTrace stackTrace) {
    instance.error('Exception', error: exception, stackTrace: stackTrace);
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

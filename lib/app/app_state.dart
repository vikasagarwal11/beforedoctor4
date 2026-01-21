import 'package:flutter/material.dart';

/// Global UI state for wireframe behaviors (offline, density, text scaling, etc.).
/// No business logic; this is only to demonstrate production-grade UI states.
enum VoiceTone { child, adult, clinician, pvAuthorizationHolder }

enum VoiceCharacterStyle { teddyBear, friendlyCharacter, healthBuddy }

extension VoiceToneLabel on VoiceTone {
  String get label {
    switch (this) {
      case VoiceTone.child:
        return 'Child-friendly';
      case VoiceTone.adult:
        return 'Adult (supportive)';
      case VoiceTone.clinician:
        return 'Clinician (doctor-style)';
      case VoiceTone.pvAuthorizationHolder:
        return 'PV Authorization Holder';
    }
  }
}

class AppState extends ChangeNotifier {
  bool _offline = false;
  bool _dense = true; // Default to compact density
  double _textScale = 0.92; // Default to 0.92 as requested
  VoiceTone _voiceTone = VoiceTone.adult;
  bool _handsFree = false;
  VoiceCharacterStyle _voiceCharacterStyle = VoiceCharacterStyle.teddyBear; // Default to Teddy Bear

  bool get offline => _offline;
  bool get dense => _dense;
  double get textScale => _textScale;
  VoiceTone get voiceTone => _voiceTone;
  bool get handsFree => _handsFree;
  VoiceCharacterStyle get voiceCharacterStyle => _voiceCharacterStyle;

  void setOffline(bool v) {
    _offline = v;
    notifyListeners();
  }

  void setDense(bool v) {
    _dense = v;
    notifyListeners();
  }

  void setTextScale(double v) {
    _textScale = v.clamp(0.85, 1.15);
    notifyListeners();
  }

  void setHandsFree(bool v) {
    _handsFree = v;
    notifyListeners();
  }

  void setVoiceTone(VoiceTone tone) {
    _voiceTone = tone;
    notifyListeners();
  }

  void setVoiceCharacterStyle(VoiceCharacterStyle style) {
    _voiceCharacterStyle = style;
    notifyListeners();
  }
}

class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    if (scope == null) {
      // Fallback: create a default AppState if scope not found
      // This can happen during hot reload or widget tree reconstruction
      debugPrint('Warning: AppStateScope not found in widget tree, using default state');
      return AppState();
    }
    return scope.notifier!;
  }
  
  /// Safe version that returns null instead of throwing
  static AppState? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    return scope?.notifier;
  }
}

/// Convenience builder widget that provides AppState to descendants.
class AppStateBuilder extends StatelessWidget {
  const AppStateBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppState state) builder;

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return builder(context, state);
  }
}

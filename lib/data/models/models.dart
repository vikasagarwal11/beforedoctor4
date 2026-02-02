export 'conversation.dart';

enum EpisodeStatus { active, completed }

class PersonProfile {
  PersonProfile({
    required this.id,
    required this.displayName,
    required this.type,
    required this.ageLabel,
  });

  final String id;
  final String displayName;
  final String type; // "Self" or "Child"
  final String ageLabel; // "Adult" or "3y"
}

class Episode {
  Episode({
    required this.id,
    required this.profileId,
    required this.productName,
    required this.productType, // "Medication" | "Vaccine"
    required this.startAt,
    this.stopAt,
    required this.status,
    this.monitoringOn = true,
    this.watchlistOn = true,
    this.shareClinicianDefault = false,
    this.sharePVDefault = false,
  });

  final String id;
  final String profileId;
  final String productName;
  final String productType;
  final DateTime startAt;
  final DateTime? stopAt;
  final EpisodeStatus status;

  bool monitoringOn;
  bool watchlistOn;
  bool shareClinicianDefault;
  bool sharePVDefault;
}

enum EventType { symptom, medicationIssue, vaccineReaction, note }

class EpisodeEvent {
  EpisodeEvent({
    required this.id,
    required this.episodeId,
    required this.type,
    required this.title,
    required this.timestamp,
    this.severity, // 0-10
    this.sharedToClinician = false,
    this.queuedOffline = false,
  });

  final String id;
  final String episodeId;
  final EventType type;
  final String title;
  final DateTime timestamp;

  final int? severity;
  bool sharedToClinician;
  bool queuedOffline;
}

enum ConditionStatus { active, resolved, monitoring }

class Condition {
  Condition({
    required this.id,
    required this.profileId,
    required this.name,
    required this.status,
    this.onset,
    this.notes,
    this.tags = const [],
  });

  final String id;
  final String profileId;
  final String name;
  final ConditionStatus status;
  final DateTime? onset;
  final String? notes;
  final List<String> tags;
}

enum MedicationType { prescription, otc, supplement, homeRemedy }

class MedicationItem {
  MedicationItem({
    required this.id,
    required this.profileId,
    required this.name,
    required this.type,
    this.dose,
    this.schedule,
    this.startAt,
    this.stopAt,
    this.reason,
    this.isActive = true,
  });

  final String id;
  final String profileId;
  final String name;
  final MedicationType type;
  final String? dose;
  final String? schedule; // e.g., "5 mL twice daily"
  final DateTime? startAt;
  final DateTime? stopAt;
  final String? reason;
  final bool isActive;
}

class FoodLog {
  FoodLog({
    required this.id,
    required this.profileId,
    required this.food,
    required this.timestamp,
    this.notes,
    this.suspectedReaction,
  });

  final String id;
  final String profileId;
  final String food;
  final DateTime timestamp;
  final String? notes;
  final String? suspectedReaction; // e.g., "stomach ache", "rash"
}

enum LinkKind { suspectedTrigger, associatedWith, causedBy, relievedBy }

class DiaryLink {
  DiaryLink({
    required this.id,
    required this.profileId,
    required this.kind,
    required this.fromType,
    required this.fromId,
    required this.toEventId,
    required this.createdAt,
  });

  final String id;
  final String profileId;
  final LinkKind kind;
  final String fromType; // 'food' | 'med' | 'condition'
  final String fromId;
  final String toEventId; // links to EpisodeEvent.id
  final DateTime createdAt;
}

// Extensions for EpisodeEvent and EventType
extension EpisodeEventExtension on EpisodeEvent {
  String get summary => title;
  List<String> get tags => [];
}

extension EventTypeExtension on EventType {
  String get label {
    switch (this) {
      case EventType.symptom:
        return 'Symptom';
      case EventType.medicationIssue:
        return 'Medication issue';
      case EventType.vaccineReaction:
        return 'Vaccine reaction';
      case EventType.note:
        return 'Note';
    }
  }
}

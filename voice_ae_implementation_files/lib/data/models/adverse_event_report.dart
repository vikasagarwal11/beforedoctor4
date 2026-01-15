import 'dart:convert';

enum ReportType { initial, followUp }
enum Seriousness { high, medium, low, unknown }
enum Outcome { recovered, recovering, ongoing, fatal, unknown }

class PatientInfo {
  final String? initials; // do NOT store full name here if you can avoid it
  final int? age;
  final String? gender;

  const PatientInfo({this.initials, this.age, this.gender});

  Map<String, dynamic> toJson() => {
        'initials': initials,
        'age': age,
        'gender': gender,
      };

  factory PatientInfo.fromJson(Map<String, dynamic> json) => PatientInfo(
        initials: json['initials'] as String?,
        age: (json['age'] is num) ? (json['age'] as num).toInt() : null,
        gender: json['gender'] as String?,
      );
}

class ProductDetails {
  final String? productName;
  final String? dosageStrength;
  final String? frequency;
  final String? indication;
  final String? lotNumber;

  const ProductDetails({
    this.productName,
    this.dosageStrength,
    this.frequency,
    this.indication,
    this.lotNumber,
  });

  Map<String, dynamic> toJson() => {
        'product_name': productName,
        'dosage_strength': dosageStrength,
        'frequency': frequency,
        'indication': indication,
        'lot_number': lotNumber,
      };

  factory ProductDetails.fromJson(Map<String, dynamic> json) => ProductDetails(
        productName: json['product_name'] as String?,
        dosageStrength: json['dosage_strength'] as String?,
        frequency: json['frequency'] as String?,
        indication: json['indication'] as String?,
        lotNumber: json['lot_number'] as String?,
      );
}

class EventDetails {
  final List<String> symptoms;              // MedDRA coding can come later
  final DateTime? onsetDate;
  final String? duration;
  final Outcome outcome;
  final String? narrative;                 // concise clinical summary

  const EventDetails({
    this.symptoms = const [],
    this.onsetDate,
    this.duration,
    this.outcome = Outcome.unknown,
    this.narrative,
  });

  Map<String, dynamic> toJson() => {
        'symptoms': symptoms,
        'onset_date': onsetDate?.toIso8601String(),
        'duration': duration,
        'outcome': outcome.name,
        'narrative': narrative,
      };

  factory EventDetails.fromJson(Map<String, dynamic> json) => EventDetails(
        symptoms: (json['symptoms'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        onsetDate: (json['onset_date'] is String)
            ? DateTime.tryParse(json['onset_date'] as String)
            : null,
        duration: json['duration'] as String?,
        outcome: Outcome.values.firstWhere(
          (v) => v.name == (json['outcome'] as String?),
          orElse: () => Outcome.unknown,
        ),
        narrative: json['narrative'] as String?,
      );
}

class AdverseEventReport {
  final String id;
  final DateTime createdAt;

  // Metadata
  final ReportType reportType;
  final Seriousness seriousness;

  // Minimum criteria fields (reporter info will typically come from signed-in user profile)
  final PatientInfo patient;
  final ProductDetails product;
  final EventDetails event;

  // Reporter (keep minimal; full contact should be securely stored server-side)
  final String? reporterRole; // patient/caregiver/hcp
  final String? reporterContact; // optional; consider masking

  // Validation flags
  final bool meetsMinimumCriteria;
  final List<String> missingRequired;

  const AdverseEventReport({
    required this.id,
    required this.createdAt,
    this.reportType = ReportType.initial,
    this.seriousness = Seriousness.unknown,
    this.patient = const PatientInfo(),
    this.product = const ProductDetails(),
    this.event = const EventDetails(),
    this.reporterRole,
    this.reporterContact,
    this.meetsMinimumCriteria = false,
    this.missingRequired = const [],
  });

  /// Minimum criteria:
  /// 1) identifiable patient (age OR gender OR initials)
  /// 2) identifiable reporter (role OR contact OR authenticated user)
  /// 3) suspect product (name)
  /// 4) adverse event (symptom(s) or narrative)
  AdverseEventReport recomputeCriteria({bool reporterKnownFromAuth = true}) {
    final missing = <String>[];

    final hasPatient =
        (patient.initials?.trim().isNotEmpty ?? false) ||
        (patient.age != null) ||
        (patient.gender?.trim().isNotEmpty ?? false);

    final hasReporter = reporterKnownFromAuth ||
        (reporterRole?.trim().isNotEmpty ?? false) ||
        (reporterContact?.trim().isNotEmpty ?? false);

    final hasProduct = (product.productName?.trim().isNotEmpty ?? false);

    final hasEvent = event.symptoms.isNotEmpty ||
        (event.narrative?.trim().isNotEmpty ?? false);

    if (!hasPatient) missing.add('patient');
    if (!hasReporter) missing.add('reporter');
    if (!hasProduct) missing.add('suspect_product');
    if (!hasEvent) missing.add('adverse_event');

    return AdverseEventReport(
      id: id,
      createdAt: createdAt,
      reportType: reportType,
      seriousness: seriousness,
      patient: patient,
      product: product,
      event: event,
      reporterRole: reporterRole,
      reporterContact: reporterContact,
      meetsMinimumCriteria: missing.isEmpty,
      missingRequired: missing,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'report_type': reportType.name,
        'seriousness': seriousness.name,
        'patient_info': patient.toJson(),
        'product_details': product.toJson(),
        'event_details': event.toJson(),
        'reporter_role': reporterRole,
        'reporter_contact': reporterContact,
        'meets_minimum_criteria': meetsMinimumCriteria,
        'missing_required': missingRequired,
      };

  String toJsonString() => jsonEncode(toJson());

  factory AdverseEventReport.fromJson(Map<String, dynamic> json) {
    return AdverseEventReport(
      id: (json['id'] as String?) ?? 'draft',
      createdAt: (json['created_at'] is String)
          ? (DateTime.tryParse(json['created_at'] as String) ?? DateTime.now())
          : DateTime.now(),
      reportType: ReportType.values.firstWhere(
        (v) => v.name == (json['report_type'] as String?),
        orElse: () => ReportType.initial,
      ),
      seriousness: Seriousness.values.firstWhere(
        (v) => v.name == (json['seriousness'] as String?),
        orElse: () => Seriousness.unknown,
      ),
      patient: PatientInfo.fromJson(
        (json['patient_info'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      product: ProductDetails.fromJson(
        (json['product_details'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      event: EventDetails.fromJson(
        (json['event_details'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      reporterRole: json['reporter_role'] as String?,
      reporterContact: json['reporter_contact'] as String?,
      meetsMinimumCriteria: json['meets_minimum_criteria'] as bool? ?? false,
      missingRequired: (json['missing_required'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}


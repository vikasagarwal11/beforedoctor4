// lib/models/adverse_event_report.dart
//
// Minimal, production-friendly AE report model with:
// - 4 minimum criteria tracking (FDA/EMA)
// - Patch application (deep merge) for incremental updates
// - Narrative preview + attestation fields

class AeCriteria {
  final bool hasIdentifiablePatient;
  final bool hasIdentifiableReporter;
  final bool hasSuspectProduct;
  final bool hasAdverseEvent;

  const AeCriteria({
    required this.hasIdentifiablePatient,
    required this.hasIdentifiableReporter,
    required this.hasSuspectProduct,
    required this.hasAdverseEvent,
  });

  bool get isValid => hasIdentifiablePatient && hasIdentifiableReporter && hasSuspectProduct && hasAdverseEvent;

  factory AeCriteria.empty() => const AeCriteria(
        hasIdentifiablePatient: false,
        hasIdentifiableReporter: false,
        hasSuspectProduct: false,
        hasAdverseEvent: false,
      );

  AeCriteria copyWith({
    bool? hasIdentifiablePatient,
    bool? hasIdentifiableReporter,
    bool? hasSuspectProduct,
    bool? hasAdverseEvent,
  }) {
    return AeCriteria(
      hasIdentifiablePatient: hasIdentifiablePatient ?? this.hasIdentifiablePatient,
      hasIdentifiableReporter: hasIdentifiableReporter ?? this.hasIdentifiableReporter,
      hasSuspectProduct: hasSuspectProduct ?? this.hasSuspectProduct,
      hasAdverseEvent: hasAdverseEvent ?? this.hasAdverseEvent,
    );
  }

  Map<String, dynamic> toJson() => {
        'patient': hasIdentifiablePatient,
        'reporter': hasIdentifiableReporter,
        'product': hasSuspectProduct,
        'event': hasAdverseEvent,
      };

  static AeCriteria fromJson(Map<String, dynamic> json) => AeCriteria(
        hasIdentifiablePatient: json['patient'] == true,
        hasIdentifiableReporter: json['reporter'] == true,
        hasSuspectProduct: json['product'] == true,
        hasAdverseEvent: json['event'] == true,
      );
}

class AdverseEventReport {
  final Map<String, dynamic> patientInfo;
  final Map<String, dynamic> reporterInfo;
  final Map<String, dynamic> productDetails;
  final Map<String, dynamic> eventDetails;

  /// Clinically important "story" of the report.
  final String narrative;

  /// Attestation (required before submission).
  final String? reporterAttestationName;
  final String? reporterDigitalSignature;
  final String? finalAttestationTimestampIso;

  final AeCriteria criteria;

  const AdverseEventReport({
    required this.patientInfo,
    required this.reporterInfo,
    required this.productDetails,
    required this.eventDetails,
    required this.narrative,
    required this.criteria,
    this.reporterAttestationName,
    this.reporterDigitalSignature,
    this.finalAttestationTimestampIso,
  });

  factory AdverseEventReport.empty() => AdverseEventReport(
        patientInfo: const {},
        reporterInfo: const {},
        productDetails: const {},
        eventDetails: const {},
        narrative: '',
        criteria: AeCriteria.empty(),
      );

  /// Apply an incremental patch (deep merge) and recompute minimum criteria.
  AdverseEventReport applyJsonPatch(Map<String, dynamic> patch) {
    Map<String, dynamic> merged(Map<String, dynamic> base, Map<String, dynamic> p) {
      final out = Map<String, dynamic>.from(base);
      p.forEach((k, v) {
        if (v is Map && out[k] is Map) {
          out[k] = merged((out[k] as Map).cast<String, dynamic>(), (v as Map).cast<String, dynamic>());
        } else {
          out[k] = v;
        }
      });
      return out;
    }

    final patient = patch['patient_info'] is Map ? merged(patientInfo, (patch['patient_info'] as Map).cast<String, dynamic>()) : patientInfo;
    final reporter = patch['reporter_info'] is Map ? merged(reporterInfo, (patch['reporter_info'] as Map).cast<String, dynamic>()) : reporterInfo;
    final product = patch['product_details'] is Map ? merged(productDetails, (patch['product_details'] as Map).cast<String, dynamic>()) : productDetails;
    final event = patch['event_details'] is Map ? merged(eventDetails, (patch['event_details'] as Map).cast<String, dynamic>()) : eventDetails;

    final narrativeUpdate = patch['narrative'] is String ? (patch['narrative'] as String) : narrative;

    final next = AdverseEventReport(
      patientInfo: patient,
      reporterInfo: reporter,
      productDetails: product,
      eventDetails: event,
      narrative: narrativeUpdate,
      criteria: criteria, // temp
      reporterAttestationName: reporterAttestationName,
      reporterDigitalSignature: reporterDigitalSignature,
      finalAttestationTimestampIso: finalAttestationTimestampIso,
    );

    return next.recomputeCriteria();
  }

  AdverseEventReport recomputeCriteria() {
    bool nonEmpty(dynamic v) {
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      if (v is List) return v.isNotEmpty;
      if (v is Map) return v.isNotEmpty;
      return true;
    }

    final hasPatient = nonEmpty(patientInfo['initials']) || nonEmpty(patientInfo['age']) || nonEmpty(patientInfo['gender']);
    final hasReporter = nonEmpty(reporterInfo['name']) || nonEmpty(reporterInfo['role']) || nonEmpty(reporterInfo['email']);
    final hasProduct = nonEmpty(productDetails['product_name']) || nonEmpty(productDetails['name']);
    final hasEvent = nonEmpty(eventDetails['symptoms']) || nonEmpty(eventDetails['description']) || nonEmpty(eventDetails['event']);

    return copyWith(
      criteria: criteria.copyWith(
        hasIdentifiablePatient: hasPatient,
        hasIdentifiableReporter: hasReporter,
        hasSuspectProduct: hasProduct,
        hasAdverseEvent: hasEvent,
      ),
    );
  }

  AdverseEventReport copyWith({
    Map<String, dynamic>? patientInfo,
    Map<String, dynamic>? reporterInfo,
    Map<String, dynamic>? productDetails,
    Map<String, dynamic>? eventDetails,
    String? narrative,
    AeCriteria? criteria,
    String? reporterAttestationName,
    String? reporterDigitalSignature,
    String? finalAttestationTimestampIso,
  }) {
    return AdverseEventReport(
      patientInfo: patientInfo ?? this.patientInfo,
      reporterInfo: reporterInfo ?? this.reporterInfo,
      productDetails: productDetails ?? this.productDetails,
      eventDetails: eventDetails ?? this.eventDetails,
      narrative: narrative ?? this.narrative,
      criteria: criteria ?? this.criteria,
      reporterAttestationName: reporterAttestationName ?? this.reporterAttestationName,
      reporterDigitalSignature: reporterDigitalSignature ?? this.reporterDigitalSignature,
      finalAttestationTimestampIso: finalAttestationTimestampIso ?? this.finalAttestationTimestampIso,
    );
  }

  Map<String, dynamic> toJson() => {
        'patient_info': patientInfo,
        'reporter_info': reporterInfo,
        'product_details': productDetails,
        'event_details': eventDetails,
        'narrative': narrative,
        'attestation': {
          'name': reporterAttestationName,
          'signature': reporterDigitalSignature,
          'timestamp': finalAttestationTimestampIso,
        },
        'criteria': criteria.toJson(),
      };

  static AdverseEventReport fromJson(Map<String, dynamic> json) {
    final report = AdverseEventReport(
      patientInfo: (json['patient_info'] as Map?)?.cast<String, dynamic>() ?? const {},
      reporterInfo: (json['reporter_info'] as Map?)?.cast<String, dynamic>() ?? const {},
      productDetails: (json['product_details'] as Map?)?.cast<String, dynamic>() ?? const {},
      eventDetails: (json['event_details'] as Map?)?.cast<String, dynamic>() ?? const {},
      narrative: (json['narrative'] as String?) ?? '',
      reporterAttestationName: ((json['attestation'] as Map?)?['name'] as String?),
      reporterDigitalSignature: ((json['attestation'] as Map?)?['signature'] as String?),
      finalAttestationTimestampIso: ((json['attestation'] as Map?)?['timestamp'] as String?),
      criteria: json['criteria'] is Map ? AeCriteria.fromJson((json['criteria'] as Map).cast<String, dynamic>()) : AeCriteria.empty(),
    );
    return report.recomputeCriteria();
  }
}

// ---- Typed helper enums & getters (retain Map storage, regain type-safety at call sites) ----

enum PatientSex { unknown, female, male, other }
enum ReportSeriousness { unknown, low, medium, high }
enum EventOutcome { unknownOutcome, recovered, recovering, notRecovered, fatal }

PatientSex _sexFrom(dynamic v) {
  final s = (v ?? '').toString().toLowerCase();
  switch (s) {
    case 'female':
    case 'f':
      return PatientSex.female;
    case 'male':
    case 'm':
      return PatientSex.male;
    case 'other':
      return PatientSex.other;
    default:
      return PatientSex.unknown;
  }
}

ReportSeriousness _seriousnessFrom(dynamic v) {
  final s = (v ?? '').toString().toLowerCase();
  switch (s) {
    case 'low':
      return ReportSeriousness.low;
    case 'medium':
      return ReportSeriousness.medium;
    case 'high':
      return ReportSeriousness.high;
    default:
      return ReportSeriousness.unknown;
  }
}

EventOutcome _outcomeFrom(dynamic v) {
  final s = (v ?? '').toString().toLowerCase();
  switch (s) {
    case 'recovered':
      return EventOutcome.recovered;
    case 'recovering':
      return EventOutcome.recovering;
    case 'not recovered':
    case 'notrecovered':
    case 'ongoing':
      return EventOutcome.notRecovered;
    case 'fatal':
    case 'death':
      return EventOutcome.fatal;
    default:
      return EventOutcome.unknownOutcome;
  }
}

extension AdverseEventReportTyped on AdverseEventReport {
  // Patient
  String? get patientInitials => (patientInfo['initials'] ?? patientInfo['patient_initials'])?.toString();
  int? get patientAge => (patientInfo['age'] is num)
      ? (patientInfo['age'] as num).toInt()
      : int.tryParse('${patientInfo['age'] ?? ''}');
  PatientSex get patientSex => _sexFrom(patientInfo['sex'] ?? patientInfo['gender']);

  // Reporter
  String? get reporterName => reporterInfo['name']?.toString();
  String? get reporterRole => reporterInfo['role']?.toString();

  // Product
  String? get productName => (productDetails['name'] ?? productDetails['product_name'])?.toString();
  String? get productDose => (productDetails['dose'] ?? productDetails['dosage_strength'])?.toString();
  String? get productFrequency => (productDetails['frequency'])?.toString();
  String? get productLot => (productDetails['lot'] ?? productDetails['lot_number'])?.toString();
  String? get productIndication => (productDetails['indication'])?.toString();

  // Event
  List<String> get eventSymptoms {
    final v = eventDetails['symptoms'];
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return const [];
  }

  String? get eventOnsetDate => (eventDetails['onset_date'] ?? eventDetails['onsetDate'])?.toString();
  EventOutcome get eventOutcome => _outcomeFrom(eventDetails['outcome']);
  ReportSeriousness get seriousness => _seriousnessFrom(eventDetails['seriousness'] ?? eventDetails['severity']);
}

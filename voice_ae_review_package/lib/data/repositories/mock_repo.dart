import '../models/models.dart';

class MockRepo {
  MockRepo({
    required this.profiles,
    required this.episodes,
    required this.events,
    required this.conditions,
    required this.medications,
    required this.foodLogs,
    required this.links,
  });

  final List<PersonProfile> profiles;
  final List<Episode> episodes;
  final List<EpisodeEvent> events;
  final List<Condition> conditions;
  final List<MedicationItem> medications;
  final List<FoodLog> foodLogs;
  final List<DiaryLink> links;

  PersonProfile getProfile(String id) => profiles.firstWhere((p) => p.id == id);

  List<Condition> conditionsForProfile(String profileId) =>
      conditions.where((c) => c.profileId == profileId).toList()
        ..sort((a, b) => (b.onset ?? DateTime(1970)).compareTo(a.onset ?? DateTime(1970)));

  List<MedicationItem> medicationsForProfile(String profileId) =>
      medications.where((m) => m.profileId == profileId).toList()
        ..sort((a, b) => (b.startAt ?? DateTime(1970)).compareTo(a.startAt ?? DateTime(1970)));

  List<FoodLog> foodLogsForProfile(String profileId) =>
      foodLogs.where((f) => f.profileId == profileId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  List<DiaryLink> linksForProfile(String profileId) =>
      links.where((l) => l.profileId == profileId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<DiaryLink> linksToEvent(String profileId, String eventId) =>
      links.where((l) => l.profileId == profileId && l.toEventId == eventId).toList();

  List<EpisodeEvent> timelineForProfile(String profileId) {
    final epIds = episodesForProfile(profileId).map((e) => e.id).toSet();
    final list = events.where((ev) => epIds.contains(ev.episodeId)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  List<Episode> episodesForProfile(String profileId) =>
      episodes.where((e) => e.profileId == profileId).toList()
        ..sort((a, b) => b.startAt.compareTo(a.startAt));

  List<EpisodeEvent> eventsForEpisode(String episodeId) =>
      events.where((e) => e.episodeId == episodeId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  Episode? activeEpisodeForProfile(String profileId) {
    final eps = episodesForProfile(profileId);
    return eps.where((e) => e.status == EpisodeStatus.active).isEmpty
        ? null
        : eps.firstWhere((e) => e.status == EpisodeStatus.active);
  }

  void addEvent(EpisodeEvent event) {
    events.insert(0, event);
  }

  static MockRepo bootstrap() {
    final profiles = [
      PersonProfile(id: 'p_self', displayName: 'You', type: 'Self', ageLabel: 'Adult'),
      PersonProfile(id: 'p_kid1', displayName: 'Kian', type: 'Child', ageLabel: '3y'),
      PersonProfile(id: 'p_kid2', displayName: 'Vihaan', type: 'Child', ageLabel: '7y'),
    ];

    final now = DateTime.now();
    final episodes = [
      Episode(
        id: 'e1',
        profileId: 'p_kid1',
        productName: 'Amoxicillin',
        productType: 'Medication',
        startAt: now.subtract(const Duration(days: 2)),
        status: EpisodeStatus.active,
        monitoringOn: true,
        watchlistOn: true,
        shareClinicianDefault: false,
        sharePVDefault: false,
      ),
      Episode(
        id: 'e2',
        profileId: 'p_kid2',
        productName: 'Influenza Vaccine',
        productType: 'Vaccine',
        startAt: now.subtract(const Duration(days: 18)),
        stopAt: now.subtract(const Duration(days: 18)),
        status: EpisodeStatus.completed,
        monitoringOn: false,
        watchlistOn: true,
      ),
      Episode(
        id: 'e3',
        profileId: 'p_self',
        productName: 'Ibuprofen',
        productType: 'Medication',
        startAt: now.subtract(const Duration(days: 55)),
        stopAt: now.subtract(const Duration(days: 52)),
        status: EpisodeStatus.completed,
      ),
    ];

    final events = [
      EpisodeEvent(
        id: 'ev1',
        episodeId: 'e1',
        type: EventType.symptom,
        title: 'Fever 101.2°F after dose',
        timestamp: now.subtract(const Duration(hours: 3)),
        severity: 5,
        queuedOffline: false,
        sharedToClinician: true,
      ),
      EpisodeEvent(
        id: 'ev2',
        episodeId: 'e1',
        type: EventType.symptom,
        title: 'New rash on arms (photo not added)',
        timestamp: now.subtract(const Duration(hours: 18)),
        severity: 4,
        queuedOffline: true,
      ),
      EpisodeEvent(
        id: 'ev3',
        episodeId: 'e2',
        type: EventType.vaccineReaction,
        title: 'Sore arm and mild fatigue',
        timestamp: now.subtract(const Duration(days: 18, hours: 2)),
        severity: 2,
      ),
      EpisodeEvent(
        id: 'ev4',
        episodeId: 'e3',
        type: EventType.note,
        title: 'Headache improved after rest',
        timestamp: now.subtract(const Duration(days: 53)),
      ),
    ];

    final conditions = <Condition>[
      Condition(
        id: 'c1',
        profileId: 'p_kid1',
        name: 'Eczema',
        status: ConditionStatus.monitoring,
        onset: now.subtract(const Duration(days: 220)),
        tags: const ['Skin', 'Allergy'],
        notes: 'Flare-ups sometimes after dairy.',
      ),
      Condition(
        id: 'c2',
        profileId: 'p_kid1',
        name: 'Seasonal allergies',
        status: ConditionStatus.active,
        onset: now.subtract(const Duration(days: 90)),
        tags: const ['Respiratory'],
      ),
      Condition(
        id: 'c3',
        profileId: 'p_self',
        name: 'Migraine',
        status: ConditionStatus.monitoring,
        onset: now.subtract(const Duration(days: 365)),
        tags: const ['Neuro'],
      ),
    ];

    final medications = <MedicationItem>[
      MedicationItem(
        id: 'm1',
        profileId: 'p_kid1',
        name: 'Amoxicillin',
        type: MedicationType.prescription,
        dose: '5 mL',
        schedule: 'Twice daily',
        startAt: now.subtract(const Duration(days: 2)),
        reason: 'Ear infection',
        isActive: true,
      ),
      MedicationItem(
        id: 'm2',
        profileId: 'p_kid1',
        name: 'Cetirizine',
        type: MedicationType.otc,
        dose: '2.5 mg',
        schedule: 'Once daily',
        startAt: now.subtract(const Duration(days: 30)),
        reason: 'Allergies',
        isActive: false,
        stopAt: now.subtract(const Duration(days: 7)),
      ),
      MedicationItem(
        id: 'm3',
        profileId: 'p_self',
        name: 'Ibuprofen',
        type: MedicationType.otc,
        dose: '200 mg',
        schedule: 'As needed',
        startAt: now.subtract(const Duration(days: 60)),
        isActive: false,
        stopAt: now.subtract(const Duration(days: 59)),
      ),
      MedicationItem(
        id: 'm4',
        profileId: 'p_kid1',
        name: 'Warm honey water',
        type: MedicationType.homeRemedy,
        schedule: 'Once at bedtime',
        startAt: now.subtract(const Duration(days: 10)),
        reason: 'Cough comfort',
        isActive: false,
      ),
    ];

    final foodLogs = <FoodLog>[
      FoodLog(
        id: 'f1',
        profileId: 'p_kid1',
        food: 'Milk (dairy)',
        timestamp: now.subtract(const Duration(hours: 18)),
        suspectedReaction: 'Stomach ache',
        notes: 'Small quantity; mild discomfort after ~1 hour.',
      ),
      FoodLog(
        id: 'f2',
        profileId: 'p_kid1',
        food: 'Strawberries',
        timestamp: now.subtract(const Duration(days: 3)),
        suspectedReaction: 'Itching',
      ),
      FoodLog(
        id: 'f3',
        profileId: 'p_self',
        food: 'Spicy food',
        timestamp: now.subtract(const Duration(days: 4)),
        suspectedReaction: 'Acid reflux',
      ),
    ];

    final links = <DiaryLink>[
      DiaryLink(
        id: 'l1',
        profileId: 'p_kid1',
        kind: LinkKind.suspectedTrigger,
        fromType: 'food',
        fromId: 'f1',
        toEventId: 'ev2',
        createdAt: now.subtract(const Duration(hours: 12)),
      ),
      DiaryLink(
        id: 'l2',
        profileId: 'p_kid1',
        kind: LinkKind.associatedWith,
        fromType: 'condition',
        fromId: 'c1',
        toEventId: 'ev3',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      DiaryLink(
        id: 'l3',
        profileId: 'p_kid1',
        kind: LinkKind.relievedBy,
        fromType: 'med',
        fromId: 'm1',
        toEventId: 'ev1',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
    ];

    return MockRepo(
      profiles: profiles,
      episodes: episodes,
      events: events,
      conditions: conditions,
      medications: medications,
      foodLogs: foodLogs,
      links: links,
    );
  }
}

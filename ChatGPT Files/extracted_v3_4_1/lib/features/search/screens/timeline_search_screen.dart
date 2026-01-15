import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';
import '../../../core/utils/format.dart';

class TimelineSearchScreen extends StatefulWidget {
  const TimelineSearchScreen({super.key, required this.repo, required this.profile});

  final MockRepo repo;
  final PersonProfile profile;

  @override
  State<TimelineSearchScreen> createState() => _TimelineSearchScreenState();
}

class _TimelineSearchScreenState extends State<TimelineSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  final Set<String> _typeFilter = {}; // labels

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<EpisodeEvent> _filtered() {
    final items = widget.repo.timelineForProfile(widget.profile.id);
    final q = _query.trim().toLowerCase();

    bool matches(EpisodeEvent e) {
      if (q.isNotEmpty) {
        final hay = '${e.summary} ${e.tags.join(' ')}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      if (_typeFilter.isNotEmpty) {
        if (!_typeFilter.contains(e.type.label)) return false;
      }
      return true;
    }

    return items.where(matches).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = _filtered();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search timeline'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.md),
        children: [
          const OfflineBanner(),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: 'Search',
              hintText: 'Example: stomach ache, dairy, rash after vaccine',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: AppTokens.sm),
          Wrap(
            spacing: AppTokens.xs,
            runSpacing: AppTokens.xs,
            children: EventType.values.map((et) {
              final selected = _typeFilter.contains(et.label);
              return FilterChip(
                label: Text(et.label),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _typeFilter.add(et.label);
                    } else {
                      _typeFilter.remove(et.label);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: AppTokens.md),
          Row(
            children: [
              Text('${items.length} results', style: t.titleSmall),
              const Spacer(),
              Text(widget.profile.displayName, style: t.bodySmall),
            ],
          ),
          const SizedBox(height: AppTokens.sm),
          ...items.map((e) {
            final links = widget.repo.linksToEvent(widget.profile.id, e.id);
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(
                          label: e.type.label,
                          icon: Icons.label_outline,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppTokens.sm),
                        Expanded(child: Text(e.summary, style: t.titleMedium)),
                      ],
                    ),
                    const SizedBox(height: AppTokens.xs),
                    Text(formatShortDateTime(e.timestamp), style: t.bodySmall),
                    if (e.tags.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.sm),
                      Wrap(
                        spacing: AppTokens.xs,
                        runSpacing: AppTokens.xs,
                        children: e.tags
                            .map((x) => Chip(label: Text(x), visualDensity: VisualDensity.compact))
                            .toList(),
                      ),
                    ],
                    if (links.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.sm),
                      LinkPills(links: links),
                    ],
                    const SizedBox(height: AppTokens.sm),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Open event details (wireframe).')),
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open'),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Link (wireframe)',
                          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link builder (wireframe).')),
                          ),
                          icon: const Icon(Icons.link),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: AppTokens.lg),
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';

import '../../core/constants/tokens.dart';
import '../../data/models/models.dart';

class LinkPills extends StatelessWidget {
  const LinkPills({super.key, required this.links});

  final List<DiaryLink> links;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;

    String labelFor(DiaryLink l) {
      final kind = switch (l.kind) {
        LinkKind.suspectedTrigger => 'Trigger',
        LinkKind.associatedWith => 'Related',
        LinkKind.causedBy => 'Caused by',
        LinkKind.relievedBy => 'Relieved',
      };
      final from = switch (l.fromType) {
        'food' => 'Food',
        'med' => 'Med',
        'condition' => 'Condition',
        _ => 'Link',
      };
      return '$kind · $from';
    }

    IconData iconFor(DiaryLink l) {
      return switch (l.fromType) {
        'food' => Icons.restaurant_outlined,
        'med' => Icons.medication_outlined,
        'condition' => Icons.list_alt_outlined,
        _ => Icons.link,
      };
    }

    return Wrap(
      spacing: AppTokens.xs,
      runSpacing: AppTokens.xs,
      children: links
          .take(3)
          .map(
            (l) => Chip(
              visualDensity: VisualDensity.compact,
              label: Text(labelFor(l), style: t.labelSmall),
              avatar: Icon(iconFor(l), size: 16),
            ),
          )
          .toList(),
    );
  }
}


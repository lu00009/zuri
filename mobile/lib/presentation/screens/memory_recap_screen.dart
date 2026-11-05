import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/datasources/remote/ai_remote_data_source.dart';
import '../providers/ai_provider.dart';
import '../providers/sync_provider.dart';

class MemoryRecapScreen extends ConsumerStatefulWidget {
  const MemoryRecapScreen({super.key});

  @override
  ConsumerState<MemoryRecapScreen> createState() => _MemoryRecapScreenState();
}

class _MemoryRecapScreenState extends ConsumerState<MemoryRecapScreen> {
  String _selectedPeriod = 'weekly';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncProvider.notifier).syncNow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final recapAsync = ref.watch(memoryRecapProvider(_selectedPeriod));

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.history_edu_outlined, size: 26),
            SizedBox(width: 8),
            Text(
              'Memory Recap',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Recap',
            onPressed: () {
              ref.invalidate(memoryRecapProvider(_selectedPeriod));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Period Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'daily',
                    label: Text('Today'),
                    icon: Icon(Icons.today, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'weekly',
                    label: Text('This Week'),
                    icon: Icon(Icons.date_range, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'monthly',
                    label: Text('This Month'),
                    icon: Icon(Icons.calendar_month, size: 16),
                  ),
                ],
                selected: {_selectedPeriod},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedPeriod = newSelection.first;
                  });
                },
              ),
            ),

            const Divider(height: 16),

            // Main Recap Body
            Expanded(
              child: recapAsync.when(
                loading: () => const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Synthesizing your memories...'),
                    ],
                  ),
                ),
                error: (err, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text(
                          'Recap Unavailable',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$err',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () =>
                              ref.invalidate(memoryRecapProvider(_selectedPeriod)),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (recap) => _buildRecapContent(context, recap),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecapContent(BuildContext context, MemoryRecap recap) {
    final theme = Theme.of(context);

    if (recap.totalNotes == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notes_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No Notes for This Period',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create or edit notes to see your AI-synthesized memory recap for this timeframe.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Overview Card
        Card(
          elevation: 0,
          color: theme.colorScheme.primaryContainer.withAlpha(80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.primary.withAlpha(50),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Your ${_formatPeriodName(recap.period)} Memory Recap',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${recap.totalNotes} notes',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  recap.overview,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Categories Sections
        if (recap.categories.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: Text(
              'Activity & Insights',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...recap.categories.map((cat) => _buildCategorySection(context, cat)),
          const SizedBox(height: 12),
        ],

        // Important Decisions
        if (recap.importantDecisions.isNotEmpty) ...[
          _buildBulletSection(
            context: context,
            title: 'Important Decisions',
            icon: Icons.gavel_outlined,
            color: Colors.teal,
            items: recap.importantDecisions,
          ),
          const SizedBox(height: 12),
        ],

        // Recurring Topics
        if (recap.recurringTopics.isNotEmpty) ...[
          _buildBulletSection(
            context: context,
            title: 'Recurring Topics',
            icon: Icons.repeat_outlined,
            color: Colors.indigo,
            items: recap.recurringTopics,
          ),
          const SizedBox(height: 12),
        ],

        // Unfinished Ideas
        if (recap.unfinishedIdeas.isNotEmpty) ...[
          _buildBulletSection(
            context: context,
            title: 'Unfinished Ideas',
            icon: Icons.lightbulb_outline,
            color: Colors.amber[800]!,
            items: recap.unfinishedIdeas,
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildCategorySection(
      BuildContext context, MemoryRecapCategory category) {
    final theme = Theme.of(context);
    final iconData = _getCategoryIcon(category.category);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconData, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  category.category,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              category.description,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...category.highlights.map(
              (hl) => _buildHighlightItem(context, hl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightItem(
      BuildContext context, MemoryRecapHighlight highlight) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        context.push('/note/${highlight.noteId}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          highlight.noteTitle,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 11, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    highlight.summary,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey[700],
                      height: 1.3,
                    ),
                  ),
                  if (highlight.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: highlight.tags.map((t) {
                        return Text(
                          '#$t',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required List<String> items,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withAlpha(60)),
      ),
      color: color.withAlpha(15),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'projects':
        return Icons.work_outline;
      case 'learning':
        return Icons.school_outlined;
      case 'ideas':
        return Icons.lightbulb_outline;
      case 'decisions':
        return Icons.gavel_outlined;
      case 'personal notes':
      default:
        return Icons.article_outlined;
    }
  }

  String _formatPeriodName(String period) {
    switch (period.toLowerCase()) {
      case 'daily':
        return 'Daily';
      case 'monthly':
        return 'Monthly';
      case 'weekly':
      default:
        return 'Weekly';
    }
  }
}

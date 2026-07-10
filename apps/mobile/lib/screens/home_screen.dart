import 'package:flutter/material.dart';
import 'package:privoice_core/privoice_core.dart';

import '../ai_service.dart';
import 'record_screen.dart';
import 'settings_screen.dart';
import 'transcript_screen.dart';

/// Home: searchable list of past meetings + a record button.
/// Private by default — nothing in the cloud.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, required this.ai});

  final MeetingRepository repository;
  final AiService ai;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Meeting> _all = [];
  bool _loading = true;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.repository.all();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  List<Meeting> get _visible {
    if (_query.trim().isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            (m.transcript ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _record() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordScreen(repository: widget.repository),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _open(Meeting m) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TranscriptScreen(
          meeting: m,
          repository: widget.repository,
          ai: widget.ai,
        ),
      ),
    );
    _load(); // minutes/action items may have changed
  }

  Future<void> _delete(Meeting m) async {
    setState(() => _all = _all.where((x) => x.id != m.id).toList());
    await widget.repository.delete(m.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${m.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.repository.insert(m);
            _load();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Search meetings…', border: InputBorder.none),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('Privoice'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
          ),
          if (!_searching) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(children: [
                Icon(Icons.lock_outline, size: 16, color: scheme.primary),
                const SizedBox(width: 4),
                Text('On-device',
                    style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _record,
        icon: const Icon(Icons.mic_rounded),
        label: const Text('Record'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _visible.isEmpty
                  ? _EmptyState(scheme: scheme, searching: _query.isNotEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: _visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final m = _visible[i];
                        return _Entrance(
                          index: i,
                          child: Dismissible(
                            key: ValueKey(m.id),
                            direction: DismissDirection.endToStart,
                            background: _deleteBg(scheme),
                            onDismissed: (_) => _delete(m),
                            child: _MeetingCard(
                                meeting: m, onTap: () => _open(m)),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _deleteBg(ColorScheme scheme) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      );
}

/// Staggered fade/slide entrance for list items.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index.clamp(0, 8)) * 60),
      curve: Curves.easeOut,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 16), child: c),
      ),
      child: child,
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.meeting, required this.onTap});

  final Meeting meeting;
  final VoidCallback onTap;

  String _subtitle() {
    final d = meeting.durationMs ~/ 1000;
    final mins = (d ~/ 60).toString();
    final secs = (d % 60).toString().padLeft(2, '0');
    final c = meeting.createdAt;
    return '${c.day}/${c.month} · $mins:$secs';
  }

  String _preview() {
    final t = (meeting.transcript ?? '').trim();
    if (t.isEmpty) return 'No transcript yet';
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasMinutes = (meeting.minutes ?? '').isNotEmpty;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(meeting.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  Text(_subtitle(),
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Text(_preview(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
              if (hasMinutes || meeting.actionItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(children: [
                  if (hasMinutes) _Pill(icon: Icons.auto_awesome, label: 'Minutes', scheme: scheme),
                  if (meeting.actionItems.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _Pill(
                        icon: Icons.checklist_rounded,
                        label: '${meeting.actionItems.length} actions',
                        scheme: scheme),
                  ],
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.scheme});
  final IconData icon;
  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: scheme.onSecondaryContainer),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSecondaryContainer)),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scheme, required this.searching});
  final ColorScheme scheme;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(searching ? Icons.search_off_rounded : Icons.graphic_eq_rounded,
            size: 64, color: scheme.primary),
        const SizedBox(height: 20),
        Center(
          child: Text(searching ? 'No matches' : 'No meetings yet',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        if (!searching)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'Tap Record to capture a meeting. It’s transcribed and '
                'summarized right here on your phone — nothing is uploaded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
          ),
      ],
    );
  }
}

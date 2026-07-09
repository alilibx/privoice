import 'package:flutter/material.dart';
import 'package:privoice_core/privoice_core.dart';

import 'record_screen.dart';
import 'transcript_screen.dart';

/// Home: the list of past meetings + a record button. The whole app in one
/// glance — private by default, nothing in the cloud.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final MeetingRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Meeting>> _meetings;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _meetings = widget.repository.all();
  }

  Future<void> _record() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordScreen(repository: widget.repository),
      ),
    );
    if (saved == true) setState(_reload);
  }

  Future<void> _open(Meeting m) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TranscriptScreen(meeting: m)),
    );
  }

  Future<void> _delete(Meeting m) async {
    await widget.repository.delete(m.id!);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privoice'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: scheme.primary),
                const SizedBox(width: 4),
                Text('On-device',
                    style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _record,
        icon: const Icon(Icons.mic_rounded),
        label: const Text('Record'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_reload),
        child: FutureBuilder<List<Meeting>>(
          future: _meetings,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final meetings = snap.data ?? const [];
            if (meetings.isEmpty) return _EmptyState(scheme: scheme);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: meetings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _MeetingCard(
                meeting: meetings[i],
                onTap: () => _open(meetings[i]),
                onDelete: () => _delete(meetings[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard(
      {required this.meeting, required this.onTap, required this.onDelete});

  final Meeting meeting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.graphic_eq_rounded, size: 64, color: scheme.primary),
        const SizedBox(height: 20),
        Center(
          child: Text('No meetings yet',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Tap Record to capture a meeting. It’s transcribed right here on '
              'your phone — nothing is uploaded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

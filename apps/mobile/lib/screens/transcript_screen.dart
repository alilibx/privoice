import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:privoice_core/privoice_core.dart';

/// Read view of one meeting's transcript. Minutes/summary + chat arrive later.
class TranscriptScreen extends StatelessWidget {
  const TranscriptScreen({super.key, required this.meeting});

  final Meeting meeting;

  String _meta() {
    final d = meeting.durationMs ~/ 1000;
    final mins = (d ~/ 60).toString();
    final secs = (d % 60).toString().padLeft(2, '0');
    final c = meeting.createdAt;
    return '${c.day}/${c.month}/${c.year} · $mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = (meeting.transcript ?? '').trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(meeting.title),
        actions: [
          if (text.isNotEmpty)
            IconButton(
              tooltip: 'Copy transcript',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transcript copied')),
                  );
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(_meta(), style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          if (text.isEmpty)
            Text('No transcript.',
                style: TextStyle(color: scheme.onSurfaceVariant))
          else
            SelectableText(
              text,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
        ],
      ),
    );
  }
}

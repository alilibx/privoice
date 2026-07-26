import 'package:flutter/material.dart';

/// Full-screen plain-text editor for a meeting's minutes.
///
/// The minutes are stored and rendered as Markdown, and this edits the raw
/// source: a full-screen field keeps the keyboard from fighting the layout on
/// long minutes, which inline editing in the Overview tab could not.
///
/// Pops the edited text on Save, or null on Cancel.
class MinutesEditorScreen extends StatefulWidget {
  const MinutesEditorScreen({super.key, required this.initialText});

  final String initialText;

  @override
  State<MinutesEditorScreen> createState() => _MinutesEditorScreenState();
}

class _MinutesEditorScreenState extends State<MinutesEditorScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _dirty => _controller.text != widget.initialText;

  Future<void> _cancel() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to these minutes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit minutes'),
        leading: TextButton(onPressed: _cancel, child: const Text('Cancel')),
        leadingWidth: 88,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(border: InputBorder.none),
          style: const TextStyle(fontSize: 15.5, height: 1.5),
        ),
      ),
    );
  }
}

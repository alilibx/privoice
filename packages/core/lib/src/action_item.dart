/// One action item extracted from a meeting, with a persisted done-state.
class ActionItem {
  const ActionItem({required this.text, this.done = false});

  final String text;
  final bool done;

  ActionItem copyWith({String? text, bool? done}) =>
      ActionItem(text: text ?? this.text, done: done ?? this.done);

  Map<String, Object?> toJson() => {'text': text, 'done': done};

  factory ActionItem.fromJson(Map<String, Object?> json) => ActionItem(
        text: json['text'] as String,
        done: (json['done'] as bool?) ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is ActionItem && other.text == text && other.done == done;

  @override
  int get hashCode => Object.hash(text, done);
}

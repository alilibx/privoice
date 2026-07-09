import 'package:privoice_core/privoice_core.dart';

/// In-memory [MeetingRepository] for widget/unit tests — no sqflite/device.
class FakeMeetingRepository implements MeetingRepository {
  FakeMeetingRepository([List<Meeting> seed = const []]) {
    for (final m in seed) {
      _items.add(m.id == null ? m.copyWith(id: _nextId++) : m);
    }
  }

  final List<Meeting> _items = [];
  int _nextId = 1;

  @override
  Future<List<Meeting>> all() async {
    final list = List<Meeting>.of(_items);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<Meeting?> byId(int id) async =>
      _items.where((m) => m.id == id).firstOrNull;

  @override
  Future<Meeting> insert(Meeting meeting) async {
    final withId = meeting.copyWith(id: _nextId++);
    _items.add(withId);
    return withId;
  }

  @override
  Future<void> update(Meeting meeting) async {
    final i = _items.indexWhere((m) => m.id == meeting.id);
    if (i >= 0) _items[i] = meeting;
  }

  @override
  Future<void> delete(int id) async => _items.removeWhere((m) => m.id == id);
}

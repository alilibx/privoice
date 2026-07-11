import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/model_manager.dart';
import 'package:privoice_models/privoice_models.dart';

import 'fakes/fake_model_downloader.dart';

void main() {
  final stt = ModelCatalog.parakeetStt;
  final llm = ModelCatalog.llama1b;

  test('starts notInstalled and not ready', () {
    final m = ModelManager(downloader: FakeModelDownloader());
    expect(m.stateOf(stt).phase, ModelPhase.notInstalled);
    expect(m.sttReady, isFalse);
    expect(m.llmReady, isFalse);
    expect(m.allReady, isFalse);
  });

  test('ensureDefaultSet downloads STT before LLM and ends ready', () async {
    final fake = FakeModelDownloader();
    final m = ModelManager(downloader: fake);
    await m.ensureDefaultSet();

    expect(fake.installCalls, [stt.id, llm.id]); // STT first
    expect(m.sttReady, isTrue);
    expect(m.llmReady, isTrue);
    expect(m.allReady, isTrue);
    expect(m.overallFraction, 1.0);
  });

  test('skips already-installed models (no re-download)', () async {
    final fake = FakeModelDownloader(installed: {stt.id, llm.id});
    final m = ModelManager(downloader: fake);
    await m.ensureDefaultSet();
    expect(fake.installCalls, isEmpty);
    expect(m.allReady, isTrue);
  });

  test('a failing model surfaces error; retry after fix succeeds', () async {
    final fake = FakeModelDownloader(failIds: {llm.id});
    final m = ModelManager(downloader: fake);
    await m.ensureDefaultSet();

    expect(m.sttReady, isTrue);
    expect(m.stateOf(llm).phase, ModelPhase.error);
    expect(m.hasError, isTrue);

    fake.failIds.clear();
    await m.ensureDefaultSet(); // retry
    expect(m.llmReady, isTrue);
    expect(m.hasError, isFalse);
  });

  test('notifies listeners on progress', () async {
    final m = ModelManager(downloader: FakeModelDownloader());
    var notes = 0;
    m.addListener(() => notes++);
    await m.ensureDefaultSet();
    expect(notes, greaterThan(0));
  });

  test('markAllReadyForTest flips readiness without downloading', () {
    final fake = FakeModelDownloader();
    final m = ModelManager(downloader: fake)..markAllReadyForTest();
    expect(m.allReady, isTrue);
    expect(fake.installCalls, isEmpty);
  });

  test('holds a wakelock only while actually downloading', () async {
    final calls = <bool>[];
    final m = ModelManager(
      downloader: FakeModelDownloader(),
      wakelock: (on) async => calls.add(on),
    );
    await m.ensureDefaultSet();
    // Enabled once when the first download starts, disabled once at the end.
    expect(calls, [true, false]);
  });

  test('never acquires the wakelock when nothing needs downloading', () async {
    final calls = <bool>[];
    final m = ModelManager(
      downloader: FakeModelDownloader(installed: {stt.id, llm.id}),
      wakelock: (on) async => calls.add(on),
    );
    await m.ensureDefaultSet();
    expect(calls, isEmpty);
  });

  test('releases the wakelock even when a download fails', () async {
    final calls = <bool>[];
    final m = ModelManager(
      downloader: FakeModelDownloader(failIds: {llm.id}),
      wakelock: (on) async => calls.add(on),
    );
    await m.ensureDefaultSet();
    expect(calls, [true, false]); // acquired for STT, released in finally
  });
}

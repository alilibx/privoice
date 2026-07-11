import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_models/privoice_models.dart';

void main() {
  group('ModelCatalog.defaultSet', () {
    test('is STT first, then the fast LLM', () {
      expect(ModelCatalog.defaultSet, [
        ModelCatalog.parakeetStt,
        ModelCatalog.llama1b,
      ]);
      expect(ModelCatalog.defaultSet.first.kind, ModelKind.stt);
      expect(ModelCatalog.defaultSet.last.kind, ModelKind.llm);
    });
  });

  group('parakeet STT spec', () {
    test('is 4 individual pre-extracted files (no archive)', () {
      final stt = ModelCatalog.parakeetStt;
      expect(stt.kind, ModelKind.stt);
      expect(stt.files.map((f) => f.fileName).toSet(), {
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'joiner.int8.onnx',
        'tokens.txt',
      });
      expect(stt.expectedFiles.toSet(), stt.files.map((f) => f.fileName).toSet());
      for (final f in stt.files) {
        expect(f.url, contains('huggingface.co'));
        expect(f.approxBytes, greaterThan(0));
      }
    });
  });

  test('no spec is an archive anymore', () {
    for (final s in [ModelCatalog.parakeetStt, ModelCatalog.llama1b, ModelCatalog.llama3b]) {
      for (final f in s.files) {
        expect(f.fileName, isNot(endsWith('.tar.bz2')));
      }
    }
  });

  group('LLM specs', () {
    test('1B and 3B are GGUF (not archives) and share the llm subdir', () {
      for (final llm in [ModelCatalog.llama1b, ModelCatalog.llama3b]) {
        expect(llm.kind, ModelKind.llm);
        expect(llm.subdir, 'llm');
        expect(llm.expectedFiles.single, endsWith('.gguf'));
      }
    });
  });

  group('approxSizeLabel', () {
    test('formats bytes as GB with one decimal', () {
      expect(ModelCatalog.llama1b.approxSizeLabel, '0.8 GB'); // 808 MB
      expect(ModelCatalog.llama3b.approxSizeLabel, '2.0 GB'); // 2020 MB
    });
  });
}

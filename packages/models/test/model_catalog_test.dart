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
    test('extracts a tar.bz2 into the 4 expected sherpa files', () {
      final stt = ModelCatalog.parakeetStt;
      expect(stt.kind, ModelKind.stt);
      expect(stt.files.single.isTarBz2, isTrue);
      expect(stt.expectedFiles, containsAll([
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'joiner.int8.onnx',
        'tokens.txt',
      ]));
    });
  });

  group('LLM specs', () {
    test('1B and 3B are GGUF (not archives) and share the llm subdir', () {
      for (final llm in [ModelCatalog.llama1b, ModelCatalog.llama3b]) {
        expect(llm.kind, ModelKind.llm);
        expect(llm.subdir, 'llm');
        expect(llm.files.single.isTarBz2, isFalse);
        expect(llm.expectedFiles.single, endsWith('.gguf'));
      }
    });
  });

  group('approxSizeLabel', () {
    test('formats bytes as GB with one decimal', () {
      expect(ModelCatalog.parakeetStt.approxSizeLabel, '0.7 GB'); // 680 MB
      expect(ModelCatalog.llama1b.approxSizeLabel, '0.8 GB'); // 808 MB
      expect(ModelCatalog.llama3b.approxSizeLabel, '2.0 GB'); // 2020 MB
    });
  });
}

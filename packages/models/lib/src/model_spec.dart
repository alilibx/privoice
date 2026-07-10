/// What kind of model this is.
enum ModelKind { stt, llm }

/// A downloadable file within a model bundle.
class ModelFile {
  const ModelFile({
    required this.url,
    required this.fileName,
    this.fallbackUrl,
    this.isTarBz2 = false,
  });

  /// Primary source (free direct-from-source: GitHub / Hugging Face).
  final String url;

  /// Optional mirror tried if [url] fails (e.g. our Firebase Storage bucket).
  final String? fallbackUrl;

  final String fileName;

  /// If true, the downloaded file is a .tar.bz2 to extract in place.
  final bool isTarBz2;
}

/// A model the app can download and use.
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.subdir,
    required this.files,
    required this.expectedFiles,
    required this.approxBytes,
  });

  final String id;
  final ModelKind kind;
  final String displayName;

  /// Directory (relative to the models root) where this model's files live.
  final String subdir;

  /// Files to download (single entry for GGUF; a tar.bz2 for STT).
  final List<ModelFile> files;

  /// Files that must exist under [subdir] for the model to be considered ready.
  final List<String> expectedFiles;

  final int approxBytes;

  String get approxSizeLabel =>
      '${(approxBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// The catalog. Direct-from-source URLs (k2-fsa releases + Hugging Face).
class ModelCatalog {
  static const parakeetStt = ModelSpec(
    id: 'parakeet-tdt-v3-int8',
    kind: ModelKind.stt,
    displayName: 'Speech-to-text (Parakeet v3)',
    subdir: 'parakeet-tdt-v3-int8',
    files: [
      ModelFile(
        url:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2',
        fallbackUrl:
            'https://storage.googleapis.com/privoice-app-models/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2',
        fileName: 'parakeet.tar.bz2',
        isTarBz2: true,
      ),
    ],
    expectedFiles: [
      'encoder.int8.onnx',
      'decoder.int8.onnx',
      'joiner.int8.onnx',
      'tokens.txt',
    ],
    approxBytes: 680 * 1024 * 1024,
  );

  static const llama1b = ModelSpec(
    id: 'llama-3.2-1b-instruct-q4',
    kind: ModelKind.llm,
    displayName: 'AI model — fast (Llama 3.2 1B)',
    subdir: 'llm',
    files: [
      ModelFile(
        url:
            'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
        fallbackUrl:
            'https://storage.googleapis.com/privoice-app-models/models/llama-3.2-1b-instruct-q4.gguf',
        fileName: 'llama-3.2-1b-instruct-q4.gguf',
      ),
    ],
    expectedFiles: ['llama-3.2-1b-instruct-q4.gguf'],
    approxBytes: 808 * 1024 * 1024,
  );

  static const llama3b = ModelSpec(
    id: 'llama-3.2-3b-instruct-q4',
    kind: ModelKind.llm,
    displayName: 'AI model — higher quality (Llama 3.2 3B)',
    subdir: 'llm',
    files: [
      ModelFile(
        url:
            'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
        fileName: 'llama-3.2-3b-instruct-q4.gguf',
      ),
    ],
    expectedFiles: ['llama-3.2-3b-instruct-q4.gguf'],
    approxBytes: 2020 * 1024 * 1024,
  );

  /// Default set every install needs: STT + the fast LLM.
  static const defaultSet = [parakeetStt, llama1b];
}

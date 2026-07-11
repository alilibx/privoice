/// Fixed-capacity FIFO of the most recent normalized mic levels (oldest first).
/// Pushing past [capacity] drops the oldest sample — the model behind the
/// scrolling waveform.
class RollingLevels {
  RollingLevels(this.capacity) : assert(capacity > 0);

  final int capacity;
  final List<double> _buf = [];

  void push(double level) {
    _buf.add(level);
    if (_buf.length > capacity) {
      _buf.removeRange(0, _buf.length - capacity);
    }
  }

  List<double> get samples => List.unmodifiable(_buf);
}

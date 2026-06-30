class PerformanceStats {
  final int fps;
  final double bandwidthBytesPerSec;
  final int latencyMs;

  const PerformanceStats({
    this.fps = 0,
    this.bandwidthBytesPerSec = 0.0,
    this.latencyMs = 0,
  });

  double get bandwidthMbps => (bandwidthBytesPerSec * 8) / (1000 * 1000);

  PerformanceStats copyWith({
    int? fps,
    double? bandwidthBytesPerSec,
    int? latencyMs,
  }) {
    return PerformanceStats(
      fps: fps ?? this.fps,
      bandwidthBytesPerSec: bandwidthBytesPerSec ?? this.bandwidthBytesPerSec,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }
}

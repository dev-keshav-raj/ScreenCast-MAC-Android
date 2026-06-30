enum Resolution {
  r720p('720p', 1280, 720),
  r1080p('1080p', 1920, 1080),
  native('Native', 0, 0),
  custom('Custom Resolution', -1, -1);

  final String label;
  final int width;
  final int height;
  const Resolution(this.label, this.width, this.height);
}

enum Fps {
  fps30('30 FPS', 30),
  fps60('60 FPS', 60);

  final String label;
  final int value;
  const Fps(this.label, this.value);
}

enum Bitrate {
  mbps5('5 Mbps', 5 * 1000 * 1000),
  mbps10('10 Mbps', 10 * 1000 * 1000),
  mbps20('20 Mbps', 20 * 1000 * 1000);

  final String label;
  final int valueInBits;
  const Bitrate(this.label, this.valueInBits);
}

enum ConnectionMode {
  adbReverse('ADB Reverse (Android Server)'),
  adbForward('ADB Forward (Mac Server)'),
  usbSocket('USB Socket');

  final String label;
  const ConnectionMode(this.label);
}

class MirrorSettings {
  final Resolution resolution;
  final Fps fps;
  final Bitrate bitrate;
  final ConnectionMode connectionMode;
  final String displayId;
  final int customWidth;
  final int customHeight;
  final bool extendDisplay;

  const MirrorSettings({
    this.resolution = Resolution.r1080p,
    this.fps = Fps.fps60,
    this.bitrate = Bitrate.mbps10,
    this.connectionMode = ConnectionMode.adbReverse,
    this.displayId = 'default',
    this.customWidth = 2400,
    this.customHeight = 1080,
    this.extendDisplay = false,
  });

  MirrorSettings copyWith({
    Resolution? resolution,
    Fps? fps,
    Bitrate? bitrate,
    ConnectionMode? connectionMode,
    String? displayId,
    int? customWidth,
    int? customHeight,
    bool? extendDisplay,
  }) {
    return MirrorSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      bitrate: bitrate ?? this.bitrate,
      connectionMode: connectionMode ?? this.connectionMode,
      displayId: displayId ?? this.displayId,
      customWidth: customWidth ?? this.customWidth,
      customHeight: customHeight ?? this.customHeight,
      extendDisplay: extendDisplay ?? this.extendDisplay,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'resolution': resolution.name,
      'fps': fps.value,
      'bitrate': bitrate.valueInBits,
      'connectionMode': connectionMode.name,
      'displayId': displayId,
      'customWidth': customWidth,
      'customHeight': customHeight,
      'extendDisplay': extendDisplay,
    };
  }
}

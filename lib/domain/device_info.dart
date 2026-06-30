class MirrorDisplay {
  final String id;
  final String name;
  final int width;
  final int height;

  const MirrorDisplay({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
  });

  factory MirrorDisplay.fromMap(Map<dynamic, dynamic> map) {
    return MirrorDisplay(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown Display',
      width: map['width'] as int? ?? 1920,
      height: map['height'] as int? ?? 1080,
    );
  }
}

class AndroidDevice {
  final String id;
  final String model;
  final String status;

  const AndroidDevice({
    required this.id,
    required this.model,
    required this.status,
  });

  factory AndroidDevice.fromMap(Map<dynamic, dynamic> map) {
    return AndroidDevice(
      id: map['id']?.toString() ?? '',
      model: map['model']?.toString() ?? 'Android Device',
      status: map['status']?.toString() ?? 'unknown',
    );
  }
}

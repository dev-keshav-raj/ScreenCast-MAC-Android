import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/mirror_settings.dart';
import '../domain/performance_stats.dart';
import '../domain/device_info.dart';

enum ConnectionStatus {
  disconnected,
  listening,
  connecting,
  streaming,
  error;
}

class LogMessage {
  final DateTime timestamp;
  final String level;
  final String message;

  LogMessage(this.message, {this.level = 'INFO'}) : timestamp = DateTime.now();
}

class PlatformChannelState {
  final ConnectionStatus status;
  final List<MirrorDisplay> displays;
  final List<AndroidDevice> devices;
  final PerformanceStats stats;
  final List<LogMessage> logs;
  final String? errorMessage;

  PlatformChannelState({
    this.status = ConnectionStatus.disconnected,
    this.displays = const [],
    this.devices = const [],
    this.stats = const PerformanceStats(),
    this.logs = const [],
    this.errorMessage,
  });

  PlatformChannelState copyWith({
    ConnectionStatus? status,
    List<MirrorDisplay>? displays,
    List<AndroidDevice>? devices,
    PerformanceStats? stats,
    List<LogMessage>? logs,
    String? errorMessage,
  }) {
    return PlatformChannelState(
      status: status ?? this.status,
      displays: displays ?? this.displays,
      devices: devices ?? this.devices,
      stats: stats ?? this.stats,
      logs: logs ?? this.logs,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class PlatformChannelService extends StateNotifier<PlatformChannelState> {
  static const MethodChannel _channel = MethodChannel('com.example.screenmirror/channel');

  PlatformChannelService() : super(PlatformChannelState()) {
    _channel.setMethodCallHandler(_handleMethodCall);
    _initData();
  }

  void log(String msg, {String level = 'INFO'}) {
    final newLog = LogMessage(msg, level: level);
    state = state.copyWith(logs: [...state.logs, newLog]);
  }

  void clearLogs() {
    state = state.copyWith(logs: []);
  }

  Future<void> _initData() async {
    log('Initializing Platform Channel Service...');
    await refreshDisplays();
    await refreshDevices();
  }

  Future<void> refreshDisplays() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getDisplays');
      if (result != null) {
        final displays = result.map((e) => MirrorDisplay.fromMap(e as Map)).toList();
        state = state.copyWith(displays: displays);
        log('Loaded ${displays.length} display(s)');
      }
    } on PlatformException catch (e) {
      log('Error fetching displays: ${e.message}', level: 'ERROR');
    }
  }

  Future<void> refreshDevices() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getDevices');
      if (result != null) {
        final devices = result.map((e) => AndroidDevice.fromMap(e as Map)).toList();
        state = state.copyWith(devices: devices);
        log('Loaded ${devices.length} USB device(s) via ADB');
      }
    } on PlatformException catch (e) {
      log('Error fetching USB devices: ${e.message}', level: 'ERROR');
    }
  }

  Future<bool> runAdbCommand(String action) async {
    try {
      log('Executing ADB Port mapping: $action...');
      final bool? success = await _channel.invokeMethod('runAdbCommand', {'action': action});
      if (success == true) {
        log('ADB Port mapping succeeded.', level: 'INFO');
        return true;
      } else {
        log('ADB Port mapping failed.', level: 'ERROR');
        return false;
      }
    } on PlatformException catch (e) {
      log('ADB error: ${e.message}', level: 'ERROR');
      return false;
    }
  }

  Future<void> startMirroring(MirrorSettings settings) async {
    try {
      state = state.copyWith(status: ConnectionStatus.connecting);
      log('Requesting stream start: ${settings.toMap()}');
      final bool? success = await _channel.invokeMethod('startMirroring', settings.toMap());
      if (success == true) {
        log('Start request accepted by native host.');
      } else {
        state = state.copyWith(status: ConnectionStatus.error, errorMessage: 'Failed to start native mirroring');
        log('Native mirroring initialization failed.', level: 'ERROR');
      }
    } on PlatformException catch (e) {
      state = state.copyWith(status: ConnectionStatus.error, errorMessage: e.message);
      log('Error starting stream: ${e.message}', level: 'ERROR');
    }
  }

  Future<void> stopMirroring() async {
    try {
      log('Requesting stream stop.');
      await _channel.invokeMethod('stopMirroring');
      state = state.copyWith(
        status: ConnectionStatus.disconnected,
        stats: const PerformanceStats(),
      );
      log('Native mirroring stopped.');
    } on PlatformException catch (e) {
      log('Error stopping stream: ${e.message}', level: 'ERROR');
    }
  }

  Future<void> startListeningAndroid(ConnectionMode mode) async {
    try {
      state = state.copyWith(status: ConnectionStatus.listening);
      log('Starting socket listener on Android in mode: ${mode.name}');
      final bool? success = await _channel.invokeMethod('startListening', {
        'connectionMode': mode.name,
      });
      if (success == true) {
        log('Android server socket is listening.');
      } else {
        state = state.copyWith(status: ConnectionStatus.error, errorMessage: 'Failed to start Android listener');
        log('Failed to start Android server socket.', level: 'ERROR');
      }
    } on PlatformException catch (e) {
      state = state.copyWith(status: ConnectionStatus.error, errorMessage: e.message);
      log('Android listener error: ${e.message}', level: 'ERROR');
    }
  }

  Future<void> stopListeningAndroid() async {
    try {
      log('Stopping socket listener on Android.');
      await _channel.invokeMethod('stopListening');
      state = state.copyWith(
        status: ConnectionStatus.disconnected,
        stats: const PerformanceStats(),
      );
      log('Android server socket stopped.');
    } on PlatformException catch (e) {
      log('Error stopping Android listener: ${e.message}', level: 'ERROR');
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onStatusChanged':
        final String statusStr = call.arguments['status'] as String;
        final String? error = call.arguments['error'] as String?;
        log('Status changed natively to: $statusStr ${error != null ? "($error)" : ""}');
        
        ConnectionStatus newStatus = ConnectionStatus.disconnected;
        for (var val in ConnectionStatus.values) {
          if (val.name == statusStr) {
            newStatus = val;
            break;
          }
        }
        state = state.copyWith(status: newStatus, errorMessage: error);
        break;
      case 'onStatsUpdated':
        final int fps = call.arguments['fps'] as int? ?? 0;
        final double bandwidth = (call.arguments['bandwidth'] as num? ?? 0).toDouble();
        final int latency = call.arguments['latencyMs'] as int? ?? 0;
        
        state = state.copyWith(
          stats: PerformanceStats(
            fps: fps,
            bandwidthBytesPerSec: bandwidth,
            latencyMs: latency,
          ),
        );
        break;
      case 'onLog':
        final String msg = call.arguments['message'] as String? ?? '';
        final String lvl = call.arguments['level'] as String? ?? 'INFO';
        log('[Native] $msg', level: lvl);
        break;
      default:
        log('Unknown callback method from native: ${call.method}', level: 'WARNING');
    }
  }
}

final platformChannelProvider = StateNotifierProvider<PlatformChannelService, PlatformChannelState>((ref) {
  return PlatformChannelService();
});

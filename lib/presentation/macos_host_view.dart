import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/platform_channel_service.dart';
import '../domain/mirror_settings.dart';

final mirrorSettingsProvider = StateProvider<MirrorSettings>((ref) => const MirrorSettings());

class MacosHostView extends ConsumerStatefulWidget {
  const MacosHostView({super.key});

  @override
  ConsumerState<MacosHostView> createState() => _MacosHostViewState();
}

class _MacosHostViewState extends ConsumerState<MacosHostView> {
  final ScrollController _logScrollController = ScrollController();
  String? _selectedDevice;

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.disconnected:
        return Colors.grey;
      case ConnectionStatus.listening:
      case ConnectionStatus.connecting:
        return Colors.amber;
      case ConnectionStatus.streaming:
        return const Color(0xFF00ADB5);
      case ConnectionStatus.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelState = ref.watch(platformChannelProvider);
    final settings = ref.watch(mirrorSettingsProvider);
    final isStreaming = channelState.status == ConnectionStatus.streaming;
    final isConnecting = channelState.status == ConnectionStatus.connecting;

    // Trigger auto-scroll on new log entries
    ref.listen(platformChannelProvider.select((value) => value.logs.length), (prev, next) {
      _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('MacMirror Host Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(platformChannelProvider.notifier).refreshDisplays();
              ref.read(platformChannelProvider.notifier).refreshDevices();
            },
            tooltip: 'Refresh devices and displays',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Column: Control panel and statistics
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Connection Status Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: _getStatusColor(channelState.status),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                             Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Status: ${channelState.status.name.toUpperCase()}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  if (channelState.errorMessage != null)
                                    Text(
                                      channelState.errorMessage!,
                                      style: const TextStyle(color: Colors.red, fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Configuration Settings
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mirroring Configuration',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF00ADB5)),
                            ),
                            const SizedBox(height: 16),

                            // Displays
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Source Display'),
                              value: channelState.displays.isNotEmpty
                                  ? (channelState.displays.any((d) => d.id == settings.displayId)
                                      ? settings.displayId
                                      : channelState.displays.first.id)
                                  : null,
                              items: channelState.displays.map((display) {
                                return DropdownMenuItem(
                                  value: display.id,
                                  child: Text('${display.name} (${display.width}x${display.height})'),
                                );
                              }).toList(),
                              onChanged: isStreaming || isConnecting
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        ref.read(mirrorSettingsProvider.notifier).state =
                                            settings.copyWith(displayId: value);
                                      }
                                    },
                            ),
                            const SizedBox(height: 12),

                            SwitchListTile(
                              title: const Text('Extend Display (Virtual Screen)'),
                              subtitle: const Text('Creates a secondary virtual display instead of mirroring.'),
                              value: settings.extendDisplay,
                              onChanged: isStreaming || isConnecting
                                  ? null
                                  : (value) {
                                      ref.read(mirrorSettingsProvider.notifier).state =
                                          settings.copyWith(extendDisplay: value);
                                    },
                              activeColor: const Color(0xFF00ADB5),
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 12),

                            // Connection Mode
                            DropdownButtonFormField<ConnectionMode>(
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Connection Mode'),
                              value: settings.connectionMode,
                              items: ConnectionMode.values.map((mode) {
                                return DropdownMenuItem(
                                  value: mode,
                                  child: Text(mode.label),
                                );
                              }).toList(),
                              onChanged: isStreaming || isConnecting
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        ref.read(mirrorSettingsProvider.notifier).state =
                                            settings.copyWith(connectionMode: value);
                                      }
                                    },
                            ),
                            const SizedBox(height: 12),

                            // Resolution
                            DropdownButtonFormField<Resolution>(
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Target Resolution'),
                              value: settings.resolution,
                              items: Resolution.values.map((res) {
                                return DropdownMenuItem(
                                  value: res,
                                  child: Text(res.label),
                                );
                              }).toList(),
                              onChanged: isStreaming || isConnecting
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        ref.read(mirrorSettingsProvider.notifier).state =
                                            settings.copyWith(resolution: value);
                                      }
                                    },
                            ),
                            if (settings.resolution == Resolution.custom) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: settings.customWidth.toString(),
                                      decoration: const InputDecoration(
                                        labelText: 'Custom Width',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) {
                                        final val = int.tryParse(value);
                                        if (val != null) {
                                          ref.read(mirrorSettingsProvider.notifier).state =
                                              settings.copyWith(customWidth: val);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: settings.customHeight.toString(),
                                      decoration: const InputDecoration(
                                        labelText: 'Custom Height',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) {
                                        final val = int.tryParse(value);
                                        if (val != null) {
                                          ref.read(mirrorSettingsProvider.notifier).state =
                                              settings.copyWith(customHeight: val);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),

                            // FPS
                            DropdownButtonFormField<Fps>(
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Target Framerate'),
                              value: settings.fps,
                              items: Fps.values.map((fpsVal) {
                                return DropdownMenuItem(
                                  value: fpsVal,
                                  child: Text(fpsVal.label),
                                );
                              }).toList(),
                              onChanged: isStreaming || isConnecting
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        ref.read(mirrorSettingsProvider.notifier).state =
                                            settings.copyWith(fps: value);
                                      }
                                    },
                            ),
                            const SizedBox(height: 12),

                            // Bitrate
                            DropdownButtonFormField<Bitrate>(
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Target Bitrate'),
                              value: settings.bitrate,
                              items: Bitrate.values.map((bit) {
                                return DropdownMenuItem(
                                  value: bit,
                                  child: Text(bit.label),
                                );
                              }).toList(),
                              onChanged: isStreaming || isConnecting
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        ref.read(mirrorSettingsProvider.notifier).state =
                                            settings.copyWith(bitrate: value);
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: isStreaming
                                ? null
                                : () async {
                                    final action = settings.connectionMode == ConnectionMode.adbForward
                                        ? 'forward'
                                        : 'reverse';
                                    await ref.read(platformChannelProvider.notifier).runAdbCommand(action);
                                  },
                            child: const Text('Config ADB USB', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isStreaming ? Colors.red : const Color(0xFF00ADB5),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: isConnecting
                                ? null
                                : () {
                                    if (isStreaming) {
                                      ref.read(platformChannelProvider.notifier).stopMirroring();
                                    } else {
                                      ref.read(platformChannelProvider.notifier).startMirroring(settings);
                                    }
                                  },
                            child: Text(
                              isStreaming ? 'Stop Streaming' : 'Start Streaming',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Telemetry details
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Live Telemetry',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildMetricTile('FPS', '${channelState.stats.fps}', 'fps'),
                                _buildMetricTile('Latency', '${channelState.stats.latencyMs} ms', 'time'),
                                _buildMetricTile(
                                  'Bandwidth',
                                  '${channelState.stats.bandwidthMbps.toStringAsFixed(2)} Mbps',
                                  'speed',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Right Column: Terminal Logs
            Expanded(
              flex: 6,
              child: Card(
                color: Colors.black,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'System Terminal Logs',
                            style: TextStyle(color: Colors.white70, fontFamily: 'Courier', fontSize: 15),
                          ),
                          TextButton(
                            onPressed: () {
                              ref.read(platformChannelProvider.notifier).clearLogs();
                            },
                            child: const Text('Clear', style: TextStyle(color: Color(0xFF00ADB5))),
                          )
                        ],
                      ),
                      const Divider(color: Colors.white24),
                      Expanded(
                        child: ListView.builder(
                          controller: _logScrollController,
                          itemCount: channelState.logs.length,
                          itemBuilder: (context, index) {
                            final log = channelState.logs[index];
                            Color logColor = Colors.white;
                            if (log.level == 'ERROR') {
                              logColor = Colors.redAccent;
                            } else if (log.level == 'WARNING') {
                              logColor = Colors.amberAccent;
                            } else if (log.level == 'INFO' && log.message.startsWith('[Native]')) {
                              logColor = const Color(0xFF00ADB5);
                            }
                            final timeStr =
                                "${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}.${log.timestamp.millisecond.toString().padLeft(3, '0')}";
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
                                  children: [
                                    TextSpan(
                                      text: '[$timeStr] ',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    TextSpan(
                                      text: '[${log.level}] ',
                                      style: TextStyle(color: logColor, fontWeight: FontWeight.bold),
                                    ),
                                    TextSpan(
                                      text: log.message,
                                      style: TextStyle(color: logColor),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00ADB5),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

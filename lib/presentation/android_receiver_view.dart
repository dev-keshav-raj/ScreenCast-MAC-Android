import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/platform_channel_service.dart';
import '../domain/mirror_settings.dart';

class AndroidReceiverView extends ConsumerStatefulWidget {
  const AndroidReceiverView({super.key});

  @override
  ConsumerState<AndroidReceiverView> createState() => _AndroidReceiverViewState();
}

class _AndroidReceiverViewState extends ConsumerState<AndroidReceiverView> {
  ConnectionMode _selectedMode = ConnectionMode.adbReverse;
  bool _showDebugOverlay = true;

  @override
  void initState() {
    super.initState();
    // Force landscape mode for mirroring view
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Hide system UI status bar for immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore orientation settings
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelState = ref.watch(platformChannelProvider);
    final isStreaming = channelState.status == ConnectionStatus.streaming;
    final isListening = channelState.status == ConnectionStatus.listening;

    return Scaffold(
      backgroundColor: Colors.black,
      body: isStreaming
          ? Stack(
              children: [
                // Native PlatformView for Android SurfaceView
                const Positioned.fill(
                  child: AndroidView(
                    viewType: 'com.example.screenmirror/surface_view',
                    creationParams: <String, dynamic>{},
                    creationParamsCodec: StandardMessageCodec(),
                  ),
                ),

                // Tap detector to toggle overlays
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showDebugOverlay = !_showDebugOverlay;
                      });
                    },
                    behavior: HitTestBehavior.translucent,
                  ),
                ),

                // Floating Debug Overlay
                if (_showDebugOverlay)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00ADB5), width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'MacMirror Telemetry',
                              style: TextStyle(
                                color: Color(0xFF00ADB5),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('FPS: ${channelState.stats.fps}', style: const TextStyle(color: Colors.white)),
                            Text(
                              'Latency: ${channelState.stats.latencyMs} ms',
                              style: const TextStyle(color: Colors.white),
                            ),
                            Text(
                              'Bandwidth: ${channelState.stats.bandwidthMbps.toStringAsFixed(2)} Mbps',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Disconnect overlay control
                if (_showDebugOverlay)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: SafeArea(
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        style: IconButton.styleFrom(backgroundColor: Colors.black54),
                        onPressed: () {
                          ref.read(platformChannelProvider.notifier).stopListeningAndroid();
                        },
                      ),
                    ),
                  ),
              ],
            )
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                    child: Card(
                      color: const Color(0xFF1E1E24),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.settings_input_hdmi,
                              size: 48,
                              color: Color(0xFF00ADB5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'MacMirror Receiver',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Mode selector
                            DropdownButtonFormField<ConnectionMode>(
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Android Network Mode',
                                labelStyle: TextStyle(color: Colors.grey),
                              ),
                              value: _selectedMode,
                              items: const [
                                DropdownMenuItem(
                                  value: ConnectionMode.adbReverse,
                                  child: Text('ADB Reverse (Server Mode - Port 8080)'),
                                ),
                                DropdownMenuItem(
                                  value: ConnectionMode.adbForward,
                                  child: Text('ADB Forward (Client Mode - localhost:8080)'),
                                ),
                              ],
                              onChanged: isListening
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        setState(() {
                                          _selectedMode = value;
                                        });
                                      }
                                    },
                            ),
                            const SizedBox(height: 24),
                            
                            // Action Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isListening ? Colors.red : const Color(0xFF00ADB5),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                onPressed: () {
                                  if (isListening) {
                                    ref.read(platformChannelProvider.notifier).stopListeningAndroid();
                                  } else {
                                    ref.read(platformChannelProvider.notifier).startListeningAndroid(_selectedMode);
                                  }
                                },
                                child: Text(
                                  isListening ? 'Stop Connection' : 'Start Connection Listener',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            
                            // User setup guidelines helper
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'How to connect:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF00ADB5),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _buildSetupStep('1. Enable USB Debugging in Developer Options.'),
                                  _buildSetupStep('2. Connect Android device to Mac over USB cable.'),
                                  _buildSetupStep(
                                    _selectedMode == ConnectionMode.adbReverse
                                        ? '3. Start listener here, then configure ADB Reverse & Start Streaming on Mac.'
                                        : '3. Run "adb forward tcp:8080 tcp:8080" on Mac, start listener here, then Start Streaming on Mac.',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSetupStep(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

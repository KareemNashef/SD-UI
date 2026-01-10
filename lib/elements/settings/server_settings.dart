// ==================== Server Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

// Server Settings Implementation

class ServerSettings extends StatefulWidget {
  const ServerSettings({super.key});
  @override
  State<ServerSettings> createState() => ServerSettingsState();
}

class ServerSettingsState extends State<ServerSettings>
    with SingleTickerProviderStateMixin {
  // ===== Class Variables ===== //
  final serverIP = TextEditingController(text: globalServerIP.value);
  final serverPort = TextEditingController(text: globalServerPort.value);

  late AnimationController _btnController;
  late Animation<double> _btnScale;
  bool _isChecking = false;

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    _btnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _btnScale = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _btnController, curve: Curves.easeInOut));
    globalServerStatus.addListener(_onStatusChanged);
  }

  @override
  void dispose() {
    globalServerStatus.removeListener(_onStatusChanged);
    serverIP.dispose();
    serverPort.dispose();
    _btnController.dispose();
    super.dispose();
  }

  // ===== Class Methods ===== //

  void _onStatusChanged() {
    if (mounted && _isChecking) {
      setState(() => _isChecking = false);
    }
  }

  // ===== Class Widgets ===== //

  Widget _buildButtonContent(bool isOnline) {
    if (_isChecking) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        key: const ValueKey('checking'),
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Ping...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    if (isOnline) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        key: ValueKey('online'),
        children: [
          Icon(Icons.link, color: Colors.white, size: 22),
          SizedBox(width: 10),
          Text(
            'Connected',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      key: ValueKey('offline'),
      children: [
        Icon(Icons.wifi_find, color: Colors.white, size: 22),
        SizedBox(width: 10),
        Text(
          'Update Connection',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: GlassContainer(
        backgroundColor: AppTheme.surfaceCard,
        borderColor: AppTheme.glassBorder,
        borderRadius: AppTheme.radiusLarge,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== Header ===== //
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.router_rounded,
                    color: AppTheme.warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SERVER',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white54,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Connection',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.95),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ===== IP Configuration ===== //
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          "IP Address",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      GlassInput(
                        controller: serverIP,
                        keyboardType: TextInputType.url,
                        hintText: '192.168.1.5',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          "Port",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      GlassInput(
                        controller: serverPort,
                        keyboardType: TextInputType.number,
                        hintText: '7860',
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ===== Status Button ===== //
            ValueListenableBuilder(
              valueListenable: globalServerStatus,
              builder: (context, status, child) {
                return GestureDetector(
                  onTapDown: (_) => _btnController.forward(),
                  onTapUp: (_) => _btnController.reverse(),
                  onTapCancel: () => _btnController.reverse(),
                  onTap: () async {
                    if (_isChecking) return;
                    setState(() => _isChecking = true);

                    globalServerIP.value = serverIP.text;
                    globalServerPort.value = serverPort.text;
                    StorageService.saveServerSettings(
                      serverIP.text,
                      serverPort.text,
                    );

                    try {
                      await checkServerStatus();
                      await Future.delayed(const Duration(milliseconds: 500));
                    } catch (e) {
                      debugPrint("Check failed: $e");
                    } finally {
                      if (mounted) setState(() => _isChecking = false);
                    }
                  },
                  child: ScaleTransition(
                    scale: _btnScale,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: status
                              ? [
                                  AppTheme.success,
                                  AppTheme.success.withValues(alpha: 0.8),
                                ]
                              : [
                                  AppTheme.accentPrimary,
                                  AppTheme.accentSecondary,
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: status
                                ? AppTheme.success.withValues(alpha: 0.3)
                                : AppTheme.accentPrimary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _buildButtonContent(status),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

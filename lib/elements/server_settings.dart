// ==================== Server Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';

// ========== Server Settings Class ========== //

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

    // Keep listener just in case status changes rapidly from elsewhere
    globalServerStatus.addListener(_onStatusChanged);
  }

  void _onStatusChanged() {
    if (mounted && _isChecking) {
      setState(() {
        _isChecking = false;
      });
    }
  }

  @override
  void dispose() {
    globalServerStatus.removeListener(_onStatusChanged);
    serverIP.dispose();
    serverPort.dispose();
    _btnController.dispose();
    super.dispose();
  }

  // ===== Class Widgets ===== //

  InputDecoration modernInputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.cyan.shade300.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.router_rounded,
                    color: Colors.orange.shade300,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 12),
                const Text(
                  'Server Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
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
                      TextField(
                        controller: serverIP,
                        keyboardType: TextInputType.url,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontFamily: 'monospace',
                        ),
                        decoration: modernInputDecoration(hint: '192.168.1.5'),
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
                      TextField(
                        controller: serverPort,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontFamily: 'monospace',
                        ),
                        decoration: modernInputDecoration(hint: '7860'),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            ValueListenableBuilder(
              valueListenable: globalServerStatus,
              builder: (context, status, child) {
                return GestureDetector(
                  onTapDown: (_) => _btnController.forward(),
                  onTapUp: (_) => _btnController.reverse(),
                  onTapCancel: () => _btnController.reverse(),
                  onTap: () async {
                    if (_isChecking) return;

                    setState(() {
                      _isChecking = true;
                    });

                    globalServerIP.value = serverIP.text;
                    globalServerPort.value = serverPort.text;
                    saveServerSettings(serverIP.text, serverPort.text);

                    // FIX: Await the check, but also set a safety timeout
                    // This ensures the button resets even if status doesn't change
                    try {
                      await checkServerStatus();
                      // Small delay for visual feedback
                      await Future.delayed(const Duration(milliseconds: 500));
                    } catch (e) {
                      debugPrint("Check failed: $e");
                    } finally {
                      if (mounted) {
                        setState(() {
                          _isChecking = false;
                        });
                      }
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
                              ? [Colors.green.shade600, Colors.teal.shade500]
                              : [Colors.cyan.shade600, Colors.blue.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: status
                                ? Colors.green.shade500.withValues(alpha: 0.3)
                                : Colors.cyan.shade500.withValues(alpha: 0.3),
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
}

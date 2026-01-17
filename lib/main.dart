// ==================== Main ==================== //

// Flutter imports
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';

// Local imports - Logic
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

// Local imports - Pages
import 'package:sd_companion/main_page.dart';

// Main App Implementation

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI style for a modern look
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const LoadingScreen(),
    );
  }
}

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});
  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  // ===== Class Variables ===== //

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _contentController;
  late Animation<double> _contentFade;

  // State
  bool _isOffline = false;
  bool _isConnecting = false;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();

    // Pulsing icon animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    // Content fade-in animation
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _contentFade = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeIn,
    );

    _contentController.forward();
    _initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _contentController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // ===== Class Methods ===== //

  Future<void> _initialize() async {
    await StorageService.loadServerSettings();
    _ipController.text = globalServerIP.value;
    _portController.text = globalServerPort.value;

    await checkServerStatus();

    if (globalServerStatus.value) {
      _startApp();
    } else {
      if (mounted) setState(() => _isOffline = true);
    }
  }

  Future<void> _handleReconnect() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
    });

    // Save and apply new settings
    globalServerIP.value = _ipController.text;
    globalServerPort.value = _portController.text;
    await StorageService.saveServerSettings(
      _ipController.text,
      _portController.text,
    );

    // Small delay for visual feedback
    await Future.delayed(const Duration(milliseconds: 800));

    await checkServerStatus();

    if (globalServerStatus.value) {
      _startApp();
    } else {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to connect to server. Check address.'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _startApp() async {
    if (mounted) {
      setState(() {
        _isOffline = false;
        _isConnecting = false;
      });
    }

    // Load necessary data and sync
    try {
      await StorageService.loadCheckpointDataMap();
      await StorageService.loadGenerationSettings();
      await StorageService.loadInpaintHistory();
      await syncCheckpointDataFromServer();
      await loadLoraDataFromServer();
    } catch (e) {
      if (kDebugMode) {
        print("Warning during loading: $e");
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainPage(key: mainPageKey)),
    );
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [
              AppTheme.accentPrimary.withValues(alpha: 0.15),
              Colors.transparent,
            ],
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: _isOffline ? _buildOfflineUI() : _buildLoadingUI(),
        ),
      ),
    );
  }

  Widget _buildLoadingUI() {
    return Center(
      key: const ValueKey('loading'),
      child: FadeTransition(
        opacity: _contentFade,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.9, end: 1.1).animate(_pulseAnimation),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accentPrimary.withValues(alpha: 0.1),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentPrimary.withValues(alpha: 0.2),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppTheme.accentPrimary,
                  size: 64,
                ),
              ),
            ),
            const SizedBox(height: 48),
            const Text(
              "Initializing Workspace",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Preparing your creative environment...",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  color: AppTheme.accentPrimary,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  minHeight: 4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineUI() {
    return Center(
      key: const ValueKey('offline'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: FadeTransition(
          opacity: _contentFade,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: AppTheme.error,
                  size: 64,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "Connection Required",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Stable Diffusion server is unreachable.",
                style: TextStyle(color: Colors.white54, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: GlassInput(
                            controller: _ipController,
                            keyboardType: TextInputType.number,
                            hintText: 'Server IP',
                            prefixIcon: Icons.lan_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: GlassInput(
                            controller: _portController,
                            keyboardType: TextInputType.number,
                            hintText: 'Port',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    const SizedBox(height: 20),
                    InkWell(
                      onTap: _handleReconnect,
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isConnecting
                                ? [Colors.grey.shade800, Colors.grey.shade900]
                                : [
                                    AppTheme.accentPrimary,
                                    AppTheme.accentSecondary,
                                  ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            if (!_isConnecting)
                              BoxShadow(
                                color: AppTheme.accentPrimary.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                          ],
                        ),
                        child: Center(
                          child: _isConnecting
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Connect to Server',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () => exit(0),
                icon: const Icon(
                  Icons.power_settings_new,
                  color: Colors.white30,
                  size: 20,
                ),
                label: const Text(
                  'Shut down app',
                  style: TextStyle(color: Colors.white30, fontSize: 14),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

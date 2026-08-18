// ==================== Main ==================== //

// Flutter imports
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Local imports - Elements
import 'package:sd_companion/elements/settings/backend_selector.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';

// Local imports - Logic
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/startup/backend_startup.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

// Local imports - Pages
import 'package:sd_companion/main_page.dart';

// Main App Implementation

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep the app's palette in sync with the active backend everywhere it's
  // set - initial load, manual switch from Settings, anything future - so
  // no call site has to remember to re-theme by hand.
  AppTheme.applyBackend(globalActiveBackendKind.value);
  globalActiveBackendKind.addListener(
    () => AppTheme.applyBackend(globalActiveBackendKind.value),
  );

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
      // Manrope as the app-wide default: every TextStyle that doesn't set
      // its own fontFamily (the overwhelming majority of them) picks this
      // up for free through Theme's inherited DefaultTextStyle, which is
      // most of what makes the whole app read as Aperture rather than
      // stock Material - only the handful of deliberate Fraunces display
      // moments (AppTheme.display/titleLarge) override it explicitly.
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppTheme.ink,
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: AppTheme.fontUI),
        primaryTextTheme: ThemeData.dark().primaryTextTheme.apply(fontFamily: AppTheme.fontUI),
      ),
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
    globalActiveBackendKind.addListener(_onBackendKindChanged);
    _initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _contentController.dispose();
    _ipController.dispose();
    _portController.dispose();
    globalActiveBackendKind.removeListener(_onBackendKindChanged);
    super.dispose();
  }

  void _onBackendKindChanged() {
    if (!mounted) return;
    setState(_syncAddressControllers);
  }

  // ===== Class Methods ===== //

  void _syncAddressControllers() {
    if (globalActiveBackendKind.value == BackendKind.forge) {
      _ipController.text = globalServerIP.value;
      _portController.text = globalServerPort.value;
    } else {
      _ipController.text = globalComfyServerIP.value;
      _portController.text = globalComfyServerPort.value;
    }
  }

  Future<void> _initialize() async {
    await StorageService.loadActiveBackendKind();
    await StorageService.loadServerSettings();
    await StorageService.loadComfyServerSettings();
    _syncAddressControllers();

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

    // Save and apply new settings for whichever backend is selected
    if (globalActiveBackendKind.value == BackendKind.forge) {
      globalServerIP.value = _ipController.text;
      globalServerPort.value = _portController.text;
      await StorageService.saveServerSettings(
        _ipController.text,
        _portController.text,
      );
    } else {
      globalComfyServerIP.value = _ipController.text;
      globalComfyServerPort.value = _portController.text;
      await StorageService.saveComfyServerSettings(
        _ipController.text,
        _portController.text,
      );
    }

    // Small delay for visual feedback
    await Future.delayed(const Duration(milliseconds: 800));

    await checkServerStatus();

    if (globalServerStatus.value) {
      _startApp();
    } else {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to connect to ${globalActiveBackendKind.value.displayName}. Check address.',
            ),
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

    // Load shared settings, then branch by active backend.
    try {
      await StorageService.loadGenerationSettings();
      await StorageService.loadInpaintHistory();
      await loadActiveBackendProfile();
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
                child: Icon(
                  Icons.blur_circular_rounded,
                  color: AppTheme.accentPrimary,
                  size: 64,
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              "Aperture",
              style: AppTheme.display.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 12),
            Text(
              "Focusing the workspace...",
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
              Text(
                "${globalActiveBackendKind.value.displayName} is unreachable.",
                style: const TextStyle(color: Colors.white54, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              const BackendSelector(),
              const SizedBox(height: 24),
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

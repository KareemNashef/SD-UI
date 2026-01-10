// ==================== Main Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_navigation_bar.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Local imports - Pages
import 'package:sd_companion/pages/inpaint_page.dart';
import 'package:sd_companion/pages/results_page.dart';
import 'package:sd_companion/pages/settings_page.dart';

// Main Page Implementation

// --- INSERT THE KEY AND FUNCTION HERE IF NOT IN GLOBALS.DART ---
// final GlobalKey<MainPageState> mainPageKey = GlobalKey<MainPageState>();
// void navigateToResultsPage() => mainPageKey.currentState?.switchToPage(1);
// ---------------------------------------------------------------

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  MainPageState createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  // ===== Controller ===== //
  late PageController _pageController;

  // ===== Pages ===== //
  final List<Widget> _pages = const [
    InpaintPage(),
    ResultsPage(), // Index 1
    SettingsPage(),
  ];

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _pageController = PageController(initialPage: globalPageIndex.value);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ===== Class Methods ===== //

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// EXTERNAL ACCESS METHOD
  /// This method allows the external function to control the page view
  void switchToPage(int index) {
    if (_pageController.hasClients) {
      _dismissKeyboard();
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutQuart,
      );
      // We don't need to set globalPageIndex here manually because
      // animateToPage will trigger _onPageChanged
    }
  }

  void _onPageChanged(int index) {
    // When swiping, update the global index so the NavBar pill animates to match
    if (globalPageIndex.value != index) {
      _dismissKeyboard();
      globalPageIndex.value = index;
    }
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        body: Container(
          // 1. GLOBAL BACKGROUND
          decoration: BoxDecoration(gradient: AppTheme.gradientBackground),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 2. PAGE CONTENT
              PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: _onPageChanged,
                children: _pages,
              ),

              // 3. FLOATING NAVIGATION BAR
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                left: 0,
                right: 0,
                bottom: isKeyboardOpen ? -100 : 20,
                child: ValueListenableBuilder(
                  valueListenable: globalPageIndex,
                  builder: (context, index, _) {
                    return GlassNavigationBar(
                      controller: _pageController,
                      items: const [
                        GlassNavigationBarItem(
                          icon: Icons.brush_rounded,
                          title: 'Inpaint',
                        ),
                        GlassNavigationBarItem(
                          icon: Icons.perm_media_rounded,
                          title: 'Results',
                        ),
                        GlassNavigationBarItem(
                          icon: Icons.tune_rounded,
                          title: 'Settings',
                        ),
                      ],
                      onTabSelected: (i) {
                        switchToPage(i); // Use the unified method
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== Main Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/custom_navigation_bar.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Local imports - Pages
import 'package:sd_companion/pages/inpaint_page.dart';
import 'package:sd_companion/pages/results_page.dart';
import 'package:sd_companion/pages/settings_page.dart';

// ========== Main Page Class ========== //

class MainPage extends StatefulWidget {
  // ===== Constructor ===== //
  const MainPage({super.key});

  @override
  MainPageState createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  // ===== Class Variables ===== //

  // Instances of pages
  final inpaintPage = const InpaintPage();
  final resultsPage = const ResultsPage();
  final settingsPage = const SettingsPage();

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
  }

  // ===== Helper Method ===== //

  // This performs the "Hard Unfocus" globally
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // ===== Class Widgets ===== //

  // Switches between main pages
  Widget pageSwitcher() {
    return ValueListenableBuilder(
      valueListenable: globalPageIndex,
      builder: (context, index, _) {
        return IndexedStack(
          index: index,
          children: [inpaintPage, resultsPage, settingsPage],
        );
      },
    );
  }

  // Custom navigation bar implementation
  Widget navigationBar() {
    return ValueListenableBuilder(
      valueListenable: globalPageIndex,
      builder: (context, index, _) {
        return CustomNavigationBar(
          items: const [
            AnimatedBottomBarItem(icon: Icons.brush, title: 'Inpaint'),
            AnimatedBottomBarItem(icon: Icons.article, title: 'Results'),
            AnimatedBottomBarItem(icon: Icons.settings, title: 'Settings'),
          ],
          onTabSelected: (i) {
            // FIX 1: Kill focus immediately when a tab is clicked
            // This prevents the keyboard from lingering or popping up on the new page
            _dismissKeyboard();
            globalPageIndex.value = i;
          },
        );
      },
    );
  }

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    // FIX 2: Global GestureDetector
    // Wrapping the Scaffold here ensures that tapping the empty background
    // on ANY page (Inpaint, Results, Settings) will dismiss the keyboard.
    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        // We use resizeToAvoidBottomInset: false if you don't want the
        // whole page to squish up when keyboard opens (optional preference)
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            pageSwitcher(),
            if (!isKeyboardOpen)
              Positioned(left: 0, right: 0, bottom: 20, child: navigationBar()),
          ],
        ),
      ),
    );
  }
}

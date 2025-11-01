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

class ServerSettingsState extends State<ServerSettings> {
  // ===== Class Variables ===== //

  // Controllers
  final serverIP = TextEditingController(text: globalServerIP.value);
  final serverPort = TextEditingController(text: globalServerPort.value);

  // ===== Lifecycle Methods ===== //

@override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    serverIP.dispose();
    serverPort.dispose();
    super.dispose();
  }
  // ===== Class Widgets ===== //

  InputDecoration modernInputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),

      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.1),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),

      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return Container(

      // Theme
      decoration: BoxDecoration(
        color: Colors.grey.shade800.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),

      // Padding
      padding: const EdgeInsets.all(16.0),

      // Content
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title with Icon
          Row(
            children: [
              Icon(
                Icons.storage_rounded,
                color: Colors.white.withValues(alpha: 0.8),
                size: 20,
              ),
              const SizedBox(width: 8),
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

          // Spacer
          const SizedBox(height: 16),

          // Server IP and Port
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Server IP
              Expanded(
                child: TextField(
                  controller: serverIP,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: modernInputDecoration(hint: 'Server IP'),
                ),
              ),

              // Spacer
              const SizedBox(width: 12),

              // Server Port
              SizedBox(
                width: 90,
                child: TextField(
                  controller: serverPort,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: modernInputDecoration(hint: 'Port'),
                ),
              ),
            ],
          ),

          // Spacer
          const SizedBox(height: 16),

          // Connect Button
          SizedBox(
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade600, Colors.purple.shade500],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {

                      // Set Server Settings
                      globalServerIP.value = serverIP.text;
                      globalServerPort.value = serverPort.text;

                      // Save Server Settings
                      saveServerSettings(serverIP.text, serverPort.text);

                      // Check if server is online
                      checkServerStatus();

                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Connect',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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
        ],
      ),
    );
  }
}

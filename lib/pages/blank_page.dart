// ==================== Main Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Main Page Class ========== //

class BlankPage extends StatefulWidget {
  // ===== Constructor ===== //
  const BlankPage({super.key});

  @override
  BlankPageState createState() => BlankPageState();
}

class BlankPageState extends State<BlankPage> {
  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Buttons')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () {},
                child: const Text('Elevated Button'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {},
                child: const Text('Outlined Button'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () {globalServerStatus.value = !globalServerStatus.value;}, child: const Text('S Button')),
              const SizedBox(height: 8),
              IconButton(icon: const Icon(Icons.home), onPressed: () {globalPageIndex.value = 0;}),
              const SizedBox(height: 8),
              FloatingActionButton(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),





              
              const SizedBox(height: 8),
              FloatingActionButton.small(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.large(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.extended(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.large(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.extended(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.large(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.extended(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.large(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.extended(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
              
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

void main() {
  runApp(const PatsDemoApp());
}

class PatsDemoApp extends StatelessWidget {
  const PatsDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'P.A.T.S Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PatsDemoHome(),
    );
  }
}

class PatsDemoHome extends StatefulWidget {
  const PatsDemoHome({super.key});

  @override
  State<PatsDemoHome> createState() => _PatsDemoHomeState();
}

class _PatsDemoHomeState extends State<PatsDemoHome> {
  final List<String> _messages = [];
  final TextEditingController _messageController = TextEditingController();

  void _addMessage(String message) {
    setState(() {
      _messages.insert(
          0, '${DateTime.now().toString().substring(11, 19)}: $message');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('P.A.T.S Demo'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Demo message input
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (_messageController.text.isNotEmpty) {
                      _addMessage(_messageController.text);
                      _messageController.clear();
                    }
                  },
                  child: const Text('Send'),
                ),
              ],
            ),
          ),

          // Demo messages
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    title: Text(_messages[index]),
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),

          // Demo info
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: const Column(
              children: [
                Text(
                  'P.A.T.S Demo App',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'This is a demo version of the P.A.T.S (Push-to-Talk System) app.',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 4),
                Text(
                  'Deployed to Firebase Hosting for web access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}

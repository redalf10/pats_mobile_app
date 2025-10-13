// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../services/firebase_service.dart';
// import '../models/transcription.dart';

// class TranscriptionHistoryPage extends StatelessWidget {
//   const TranscriptionHistoryPage({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final db = context.read<FirebaseDbService>();
//     return Scaffold(
//       appBar: AppBar(title: const Text('Transcription History')),
//       body: StreamBuilder<List<Transcription>>(
//         stream: db.watchAllNewestFirst(),
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Center(child: CircularProgressIndicator());
//           }
//           final items = snapshot.data ?? [];
//           if (items.isEmpty) {
//             return const Center(child: Text('No transcriptions yet.'));
//           }
//           return ListView.builder(
//             itemCount: items.length,
//             itemBuilder: (context, index) {
//               final entry = items[index];
//               final time = DateTime.fromMillisecondsSinceEpoch(entry.timestamp);
//               return ListTile(
//                 leading: const Icon(Icons.record_voice_over),
//                 title: Text(entry.userName,
//                     style: const TextStyle(fontWeight: FontWeight.bold)),
//                 subtitle: Text(entry.text),
//                 trailing: Text(
//                   '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
//                   style: const TextStyle(fontSize: 12, color: Colors.grey),
//                 ),
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }

// import 'dart:async';
// import '../models/transcription_web.dart';

// // Web-compatible implementation of LocalDbService
// class LocalDbService {
//   late final StreamController<List<Transcription>> _transcriptionsController;
//   bool _isInitialized = false;
//   List<Transcription> _transcriptions = [];

//   bool get isInitialized => _isInitialized;

//   Future<void> init() async {
//     try {
//       _transcriptionsController =
//           StreamController<List<Transcription>>.broadcast(
//         onListen: _emitTranscriptions,
//       );
//       _isInitialized = true;
//       print('LocalDbService (web) initialized successfully');
//     } catch (e) {
//       print('Error initializing LocalDbService: $e');
//       rethrow;
//     }
//   }

//   Transcription addTranscription({
//     required String userId,
//     required String userName,
//     required String text,
//     required int timestamp,
//   }) {
//     final t = Transcription(
//       id: _transcriptions.length + 1,
//       userId: userId,
//       userName: userName,
//       text: text,
//       timestamp: timestamp,
//     );
//     _transcriptions.add(t);
//     // ignore: avoid_print
//     print(
//         'LocalDbService.addTranscription -> saved id=${t.id}, user=$userName, text="$text"');
//     _emitTranscriptions();
//     return t;
//   }

//   List<Transcription> getAllNewestFirst() {
//     final sorted = List<Transcription>.from(_transcriptions);
//     sorted.sort((a, b) => b.timestamp.compareTo(a.timestamp));
//     return sorted;
//   }

//   Stream<List<Transcription>> watchAllNewestFirst() {
//     if (!_isInitialized) {
//       print('LocalDbService not initialized yet, returning empty stream');
//       return Stream.value([]);
//     }
//     // Immediately emit current data, then forward subsequent updates
//     return Stream<List<Transcription>>.multi((controller) {
//       try {
//         controller.add(getAllNewestFirst());
//       } catch (e) {
//         controller.addError(e);
//       }
//       final sub = _transcriptionsController.stream.listen(
//         controller.add,
//         onError: controller.addError,
//         onDone: controller.close,
//       );
//       controller.onCancel = () => sub.cancel();
//     });
//   }

//   void _emitTranscriptions() {
//     if (!_transcriptionsController.isClosed) {
//       final list = getAllNewestFirst();
//       // ignore: avoid_print
//       print(
//           'LocalDbService._emitTranscriptions -> emitting ${list.length} items');
//       _transcriptionsController.add(list);
//     }
//   }

//   void clearAllTranscriptions() {
//     if (_isInitialized) {
//       _transcriptions.clear();
//       _emitTranscriptions();
//     }
//   }

//   bool updateTranscriptionText({
//     required int id,
//     required String newText,
//   }) {
//     if (!_isInitialized) return false;
//     try {
//       final index = _transcriptions.indexWhere((t) => t.id == id);
//       if (index == -1) return false;
//       _transcriptions[index].text = newText;
//       _emitTranscriptions();
//       return true;
//     } catch (e) {
//       // ignore: avoid_print
//       print('Error updating transcription id=$id: $e');
//       return false;
//     }
//   }

//   void dispose() {
//     _transcriptionsController.close();
//   }
// }

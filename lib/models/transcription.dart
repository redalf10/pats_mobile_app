class Transcription {
  int id;
  String userId;
  String userName;
  String text;
  int timestamp;
  String? audioData; // Base64 encoded audio data stored in database
  String? audioFileName; // Original filename of the audio file

  Transcription({
    this.id = 0,
    required this.userId,
    required this.userName,
    required this.text,
    required this.timestamp,
    this.audioData,
    this.audioFileName,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id.toString(),
      'userId': userId,
      'userName': userName,
      'text': text,
      'timestamp': timestamp,
      'audioData': audioData,
      'audioFileName': audioFileName,
    };
  }

  factory Transcription.fromJson(Map<String, dynamic> json) {
    return Transcription(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      text: json['text'] ?? '',
      timestamp: json['timestamp'] ?? 0,
      audioData: json['audioData'],
      audioFileName: json['audioFileName'],
    );
  }
}

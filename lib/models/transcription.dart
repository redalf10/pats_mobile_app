class Transcription {
  int id;
  String userId;
  String userName;
  String text;
  int timestamp;

  Transcription({
    this.id = 0,
    required this.userId,
    required this.userName,
    required this.text,
    required this.timestamp,
  });
}

# P.A.T.S (Pilot & Air Traffic Services)

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Gemini AI](https://img.shields.io/badge/Gemini%20AI-4285F4?style=for-the-badge&logo=google-gemini&logoColor=white)](https://ai.google.dev/)

P.A.T.S is a cutting-edge mobile application designed to streamline communication between pilots and air traffic services. It combines traditional walkie-talkie functionality with modern AI capabilities, providing real-time transcription, role-based interaction, and intelligent conversation analysis.

## 🚀 Key Features

- **Real-time Walkie-Talkie**: A high-performance Push-To-Talk (PTT) interface with live waveform visualization for clear, reliable voice communication.
- **Role-Based Interaction**: Supports specialized roles including **Pilot 1**, **Pilot 2**, **Tower**, and **Inspector**, each with distinct visual indicators.
- **Secure Room System**: Create or join private communication channels using unique, shareable room codes.
- **AI-Powered Transcription**: Automatic speech-to-text conversion of all interactions, ensuring no critical information is missed.
- **Gemini AI Analysis**: Leverages Google Gemini Pro to provide intelligent summaries, insights, and analysis of flight communications.
- **Hybrid Data Persistence**: Robust storage using **ObjectBox** for high-performance local history and **Firebase Realtime Database** for cross-device synchronization.
- **Premium Design**: A modern, sleek UI featuring dark mode, glassmorphism, and smooth micro-animations for a high-end user experience.

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev) (Dart)
- **State Management**: [Provider](https://pub.dev/packages/provider)
- **Backend Services**: 
  - Firebase Authentication (Google Sign-In)
  - Firebase Realtime Database
- **Artificial Intelligence**: [Google Generative AI (Gemini Pro)](https://ai.google.dev/)
- **Local Database**: [ObjectBox](https://objectbox.io/)
- **Audio Processing**: Audioplayers, Flutter Sound, and Wave.
- **Networking**: WebSockets for low-latency communication.

## 📦 Getting Started

### Prerequisites
- Flutter SDK (latest stable version)
- Dart SDK
- Android Studio / VS Code
- A Firebase project

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/pats_app.git
   ```
2. Navigate to the project directory:
   ```bash
   cd pats_app
   ```
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the application:
   ```bash
   flutter run
   ```

## ⚙️ Configuration

To enable AI features and Firebase synchronization:
1. Create a Firebase project and add your `google-services.json` (Android) or `GoogleService-Info.plist` (iOS).
2. Obtain a Google Gemini API Key from the [AI Studio](https://aistudio.google.com/).
3. Configure your environment variables or update the `config.dart` file with your credentials.

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

---
*Developed with ❤️ for the aviation community.*

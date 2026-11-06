# CampusSync

### Your campus. Your schedule. Everything in sync.

CampusSync is a Flutter-based college companion application designed to bring essential campus information into one place. From class timetables and room availability to examination schedules and college announcements, CampusSync makes everyday campus life easier to navigate.

<p align="center">
  <a href="https://github.com/kasheeesh08/CampusSync/releases/latest">
    <img src="https://img.shields.io/github/v/release/kasheeesh08/CampusSync?style=for-the-badge&color=2563eb" alt="Latest Release">
  </a>
  <a href="https://github.com/kasheeesh08/CampusSync/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/kasheeesh08/CampusSync?style=for-the-badge&color=16a34a" alt="License">
  </a>
  <img src="https://img.shields.io/badge/Flutter-Framework-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android">
</p>

---

## Overview

CampusSync provides students with a centralized platform for accessing academic and campus-related information.

Instead of navigating multiple sources, students can use one application to check their daily schedules, explore campus rooms, track examinations and stay informed about important updates.

## Features

| Feature | Description |
|---|---|
| **Student Dashboard** | Personalized dashboard with academic information. |
| **Timetable** | View class schedules, subjects, faculty and classroom details. |
| **Room Availability** | Explore campus floors and room occupancy information. |
| **Examination Schedule** | Access upcoming examination dates and details. |
| **Academic Calendar** | Stay informed about academic activities and important dates. |
| **Announcements** | View college events, competitions and other updates. |
| **Elective Selection** | Select and manage open electives through your profile. |
| **Student Authentication** | Registration, sign-in and administrator approval workflow. |

## Technology Stack

**Frontend**
- Flutter
- Dart

**Backend and Database**
- Firebase Authentication
- Cloud Firestore

**Development and Testing**
- Flutter Test
- Firebase Emulator Suite
- JavaScript / Node.js
- Python

## Getting Started

Follow these steps to run CampusSync locally.

### Prerequisites

Install the following:

- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Android Studio](https://developer.android.com/studio)
- [Git](https://git-scm.com/)

Verify your Flutter installation:

```bash
flutter doctor
```

### 1. Clone the repository

```bash
git clone https://github.com/kasheeesh08/CampusSync.git
cd CampusSync/app
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Configure Firebase

CampusSync supports demo, emulator and live backend configurations.

The real Firebase configuration files are intentionally excluded from this repository.

For demo mode, create the local configuration file from the provided template.

**Windows PowerShell:**

```powershell
Copy-Item lib/firebase_options_live.example.dart lib/firebase_options_live.dart
```

Then run:

```bash
flutter run
```

For live mode, configure your own Firebase project using the FlutterFire CLI.

```bash
dart pub global activate flutterfire_cli
```

Configure your project:

```bash
flutterfire configure --project=<your-project-id> --platforms=android,web --android-package-name=com.campussync.campussync --out=lib/firebase_options_live.dart
```

Enable Email/Password authentication and configure Cloud Firestore in your Firebase project.

Refer to [DEPLOYMENT.md](docs/DEPLOYMENT.md) for additional setup instructions.

### 4. Run the application

```bash
flutter run
```

To explicitly launch the live backend:

```bash
flutter run --dart-define=CAMPUSSYNC_BACKEND=live
```

## Project Structure

```text
CampusSync/
│
├── app/
│   ├── lib/                 # Flutter application source
│   ├── assets/              # Application assets and seed data
│   ├── test/                # Flutter tests
│   ├── android/             # Android platform configuration
│   ├── web/                 # Web application files
│   ├── pubspec.yaml         # Dependencies and project config
│   └── README.md
│
├── firebase/
│   ├── firestore.rules      # Firestore security rules
│   ├── firestore.indexes.json
│   ├── test/                # Firebase rules and seed tests
│   └── *.mjs                # Firebase utilities
│
├── e2e/                     # End-to-end tests
├── tools/                   # Development utilities
├── docs/                    # Project documentation
│
├── .gitignore
├── LICENSE
└── README.md
```

## Download

Want to try CampusSync?

Get the latest Android release here:

<p align="center">
  <a href="https://github.com/kasheeesh08/CampusSync/releases/latest">
    <img src="https://img.shields.io/badge/Download-Android%20APK-2563eb?style=for-the-badge&logo=android&logoColor=white" alt="Download Android APK">
  </a>
</p>

**Note:** The current v1.0.0 APK is a testing build signed with a debug key. It is intended for testing and is not a production-signed release.

## Testing

Run Flutter static analysis:

```bash
flutter analyze
```

Run the Flutter test suite:

```bash
flutter test
```

Firebase rules and seed tests can be run using the local Firebase Emulator Suite. See the project documentation for details.

## Contributing

Contributions, suggestions and bug reports are welcome.

1. Fork the repository.
2. Create a feature branch.
3. Make your changes.
4. Submit a pull request.

For major changes, open an issue first to discuss the proposed update.

## License

CampusSync is distributed under the [MIT License](LICENSE).

---

<p align="center">
  Built with Flutter. Designed to simplify campus life.
  <br>
  <a href="https://github.com/kasheeesh08">Kashish</a> ·
  <a href="https://github.com/kasheeesh08/CampusSync">GitHub Repository</a>
</p>

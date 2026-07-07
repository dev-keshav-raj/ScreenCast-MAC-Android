# 📱🖥️ ScreenMirror

> Cross-platform USB Display Casting built with Flutter.

ScreenMirror is a high-performance desktop-to-mobile display casting application that allows users to mirror a macOS screen directly onto an Android phone or tablet using a USB Type-C or USB cable.

Unlike traditional wireless screen casting solutions, ScreenMirror prioritizes ultra-low latency, smoother frame delivery, and offline connectivity by transmitting display data through USB.

---

# ✨ Features

- ⚡ Ultra Low Latency Screen Casting
- 🔌 USB Type-C / USB Cable Connection
- 🖥️ macOS → Android Display Mirroring
- 📱 Supports Android Phones & Tablets
- 🎯 Optimized Rendering Pipeline
- 🚀 High FPS Video Streaming
- 🔄 Automatic Device Detection
- 📶 Works Completely Offline
- 🔒 Secure Local Communication
- 💻 Cross Platform Flutter Codebase

---

# Architecture

```
macOS Desktop
      │
Screen Capture Engine
      │
Frame Encoder
      │
USB Communication Layer
      │
════════ USB Cable ════════
      │
Android Receiver
      │
Frame Decoder
      │
Flutter Renderer
      │
Display Output
```

---

# Tech Stack

## Frontend

- Flutter
- Material 3
- Dart

## Platforms

- macOS
- Android

## Communication

- USB Type-C
- Platform Channels

## Rendering

- Custom Frame Rendering
- Optimized Image Buffer Processing

---

# Engineering Highlights

## Cross Platform

Single Flutter codebase supporting:

- macOS
- Android

---

## High Performance Streaming

- Low latency frame pipeline
- Optimized frame buffering
- Reduced dropped frames
- Smooth rendering

---

## USB Communication

- Native platform channel integration
- Device detection
- Secure USB communication
- Offline operation

---

## Platform Integration

- Native macOS APIs
- Android USB APIs
- Flutter Platform Channels

---

# Folder Structure

```
lib/
├── models/
├── services/
├── providers/
├── screens/
├── widgets/
├── platform/
└── utils/
```

---

# Future Improvements

- Audio Streaming
- Multiple Display Support
- Touch Input Reverse Control
- Clipboard Sync
- File Transfer
- Wireless Mode
- Hardware Video Encoding
- Adaptive Bitrate Streaming

---

# Getting Started

## Requirements

- Flutter 3.22+
- Dart SDK
- Android Device
- macOS

## Installation

```bash
git clone https://github.com/dev-keshav-raj/ScreenMirror.git

cd ScreenMirror

flutter pub get

flutter run
```

---

# Author

**Keshav Raj**

Flutter • Android • macOS Developer

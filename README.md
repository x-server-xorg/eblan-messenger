# Eblan-Messenger

Telegram-like messenger with Web, Android, Linux, and Windows clients.

## Project Structure

```
eblan-messenger/
├── server/          # Node.js + TypeScript backend
├── client/          # Flutter (Web + Android + Linux + Windows)
└── README.md
```

## Quick Start

### 1. Start the Server

```bash
cd server
npm install
npm run dev
```

Server runs on `http://0.0.0.0:3000`.

### 2. Run the Client

```bash
cd client
flutter pub get
```

#### Web
```bash
flutter run -d chrome
```

#### Android
```bash
flutter run -d android
# or build APK:
flutter build apk --debug
# universal APK (all architectures):
flutter build apk --debug --no-split-per-abi
```

#### Linux
```bash
flutter run -d linux
# or build:
flutter build linux
```

#### Windows
```bash
flutter run -d windows
# or build:
flutter build windows
```

## Features

-   Registration/Login with `@username` + password + custom server address
-   Real-time messaging via WebSocket
-   File, photo, video sharing
-   Voice messages (record and playback)
-   User search by `@username`
-   Profile management (avatar, username, bio)
-   Account deletion
-   Dark/Light theme (Telegram-style design)
-   All user data, files, messages stored on the server

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/auth/register` | Register new user |
| POST | `/api/auth/login` | Login |
| GET | `/api/auth/me` | Get current user |
| GET | `/api/users/search?q=` | Search users |
| GET | `/api/users/:id` | Get user by ID |
| PUT | `/api/users/me` | Update profile |
| DELETE | `/api/users/me` | Delete account |
| GET | `/api/messages/:userId` | Get chat history |
| GET | `/api/messages/chats/list` | Get chats list |
| POST | `/api/files/upload` | Upload file |
| GET | `/api/files/:type/:filename` | Download file |

## WebSocket Events

-   `message:send` → Send message
-   `message:received` ← Receive message
-   `user:typing` → User is typing
-   `user:stop_typing` → User stopped typing
-   `user:online` ← User came online
-   `user:offline` ← User went offline

## Tech Stack

-   **Server**: Node.js, TypeScript, Express, Socket.IO, SQLite, JWT
-   **Client**: Flutter (Dart), Provider, Dio, Socket.IO Client

## Requirements

-   Node.js 18+
-   Flutter SDK 3.x (for building clients)
-   Android SDK (for building Android APK)

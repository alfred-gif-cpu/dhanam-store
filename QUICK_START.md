# Dhanam Store - Quick Start Guide

## Daily Startup

### Step 1: Open VS Code
Open folder: `D:\dhanam_store`

### Step 2: Start Backend (Terminal 1)
```
cd backend
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Step 3: Start Flutter App (Terminal 2)
```
flutter run
```

---

## Flutter Commands

| Command | Purpose |
|---------|---------|
| `flutter run` | Run app on connected device/emulator |
| `flutter clean` | Clean build files (fixes most build errors) |
| `flutter pub get` | Install/update packages |
| `flutter run --release` | Run in release mode |
| `flutter build apk` | Build APK for Android |
| `flutter build appbundle` | Build AAB for Play Store |
| `flutter devices` | List connected devices |
| `flutter doctor` | Check Flutter setup |

---

## Git Commands

| Command | Purpose |
|---------|---------|
| `git status` | See changed files |
| `git add .` | Stage all changes |
| `git commit -m "message"` | Commit with message |
| `git push origin main` | Push to GitHub |
| `git pull origin main` | Pull latest from GitHub |
| `git log --oneline -10` | See last 10 commits |
| `git diff` | See what changed |
| `git stash` | Temporarily save changes |
| `git stash pop` | Restore stashed changes |

### Push all updates to GitHub:
```
git add .
git commit -m "Your commit message here"
git push origin main
```

---

## Admin Credentials
- Email: admin@dhanamstore.com
- Password: ChangeMe123! (change on first login)

## Backend API Docs
- Swagger: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Important Paths
- Flutter app: `D:\dhanam_store\lib\`
- Backend API: `D:\dhanam_store\backend\`
- Product images: `D:\dhanam_store\backend\static\images\`
- MongoDB: Cloud (Atlas) - always running

## Troubleshooting
- **Backend won't start?** → `cd backend && pip install -r requirements.txt`
- **Flutter build fails?** → `flutter clean && flutter pub get && flutter run`
- **Gradle error?** → Stop daemon: `cd android && .\gradlew.bat --stop`
- **bson error?** → Use `python -m uvicorn` NOT just `uvicorn`

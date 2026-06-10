# Travelly (Flutter) — Sustainable Journey Planner

Cross-platform rebuild of Travelly for **Android, iOS and Web**, using Flutter.
No Google dependency — maps are OpenStreetMap, routing is OSRM, address search is
Photon, transit stops come from OpenStreetMap Overpass, and weather from Open-Meteo
(all free, no API keys).

## Features
- Live GPS current location on an OpenStreetMap map
- Smart address autocomplete (type a street, pick the exact Rd/St)
- Now / Depart / Arrive planning with **Material calendar + clock pickers** (built-in)
- Route options list with real distance and Depart/Arrive times
- Travel modes: Walk, Cycle, E-scooter, Public transport, Drive — each with calories & CO2
- Public-transport trip details with real bus stop / train station names (Google-Maps style)
- Start trip (live tracking) or Schedule trip (saved on device)
- Trip history, Insights, Profile, Help, Saved & Scheduled

## Project layout
```
travelly_flutter/
├── pubspec.yaml
├── lib/
│   ├── main.dart            # App, theme, AppState, Home + Drawer
│   ├── models.dart          # Modes/metrics, RouteOption, ScheduledTrip
│   ├── services.dart        # Photon, OSRM, Overpass, Open-Meteo, GPS
│   └── screens/
│       ├── plan.dart        # Plan journey + autocomplete + date/time pickers
│       ├── routes.dart      # Route options list + map
│       ├── details.dart     # Trip details + transit itinerary + Start/Schedule
│       ├── active.dart      # Live trip tracking
│       └── extras.dart      # Trips, Saved, Insights, Profile, Help
```

## First-time setup
You need Flutter installed: https://docs.flutter.dev/get-started/install

```bash
# 1) From inside this folder, generate the platform projects (android/ ios/ web/)
flutter create . --org com.travelly --platforms=android,ios,web

# 2) Get packages
flutter pub get
```

### Add location permissions
**Android** — in `android/app/src/main/AndroidManifest.xml`, inside `<manifest>` (above `<application>`):
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
```
Set `minSdkVersion 21` (or higher) in `android/app/build.gradle`.

**iOS** — in `ios/Runner/Info.plist`, add:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Travelly uses your location to plan journeys from where you are.</string>
```

**Web** — geolocation works automatically over HTTPS (and on localhost).

## Run
```bash
flutter run                 # connected Android/iOS device or emulator
flutter run -d chrome       # web
```

## Build for release
```bash
# Android
flutter build apk --release            # app-release.apk
flutter build appbundle --release      # for Google Play

# iOS (on macOS, then Xcode/TestFlight)
flutter build ios --release

# Web (deploy build/web/ to any static host or GitHub Pages)
flutter build web --release
```

### Deploy web to GitHub Pages
```bash
flutter build web --release --base-href /Travelly/
# push the contents of build/web to the gh-pages branch (or /docs)
```

## Notes
- Route alternatives use OSRM's public demo server (driving profile); walk/cycle/scooter
  reuse the road geometry with mode-appropriate time. For exact pedestrian/cycle paths and
  real transit timetables, plug in a routing key / GTFS feed.
- Transit stop names are real (OpenStreetMap). Live route numbers/timetables need a GTFS feed.

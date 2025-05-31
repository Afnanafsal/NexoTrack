# 📍 NexoTrack
### Advanced Location Tracking & Attendance Management System

<div align="center">
  <img src="assets/applogo.png" alt="NexoTrack Logo" width="128" height="128">
  
  [![Flutter](https://img.shields.io/badge/Flutter-3.7.2+-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
  [![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
  [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)
  
  *Revolutionizing workforce management with intelligent geofencing and real-time tracking*
</div>

---

## 🚀 Overview

**NexoTrack** is a cutting-edge Flutter application designed for comprehensive location tracking and attendance management. Built with Firebase integration, it provides real-time monitoring, geofencing capabilities, and automated attendance tracking for modern businesses.

### 🎯 Key Features

- **🔐 Role-Based Authentication** - Secure admin and staff login system
- **📍 Real-Time Location Tracking** - Live GPS monitoring with 25m geofence accuracy
- **⚡ Auto-Attendance System** - Automatic punch-in/out based on location
- **📊 Advanced Analytics** - Comprehensive dashboard with attendance insights
- **🗺️ Interactive Maps** - OpenStreetMap integration for location visualization
- **📱 Cross-Platform** - Works seamlessly on Android, iOS, Web, and Windows
- **☁️ Cloud Integration** - Firebase Firestore for real-time data synchronization


---

## 🎨 Screenshots

*Screenshots will be added here showcasing the beautiful UI of both admin and staff dashboards*

---

## 🏗️ Architecture

### Tech Stack
- **Frontend**: Flutter 3.7.2+
- **Backend**: Firebase (Auth, Firestore, Cloud Functions)
- **Maps**: OpenStreetMap (OSM) with Flutter Map
- **State Management**: StatefulWidget with Provider patterns
- **Location Services**: Geolocator & Permission Handler
- **Charts**: Syncfusion Flutter Charts

### Project Structure
```
lib/
├── admin_dashboard.dart       # Admin control panel
├── staff_dashboard.dart       # Staff tracking interface
├── login.dart                 # Authentication screen
├── signup.dart                # User registration
├── manage_staff.dart          # Staff management system
├── manage_locations.dart      # Office location setup
├── live_location.dart         # Real-time tracking view
├── location_picker.dart       # Interactive location selector
├── Punching_history.dart      # Attendance history
├── FirestoreService.dart      # Database operations
├── UserModel.dart             # User data models
├── locationservice.dart       # Location utilities
├── reset.dart                 # Password reset
└── splashscreen.dart          # App launch screen
```

---

## 🛠️ Installation & Setup

### Prerequisites
- Flutter SDK 3.7.2 or higher
- Dart SDK 3.0+
-  VS Code with Flutter extensions
- Firebase account with project setup

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/nexotrack.git
cd nexotrack
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Firebase Configuration
1. Create a new Firebase project at [Firebase Console](https://console.firebase.google.com)
2. Enable Authentication (Email/Password)
3. Create a Firestore database
4. Download and place configuration files:
   - `android/app/google-services.json` (Android)
   - `ios/Runner/GoogleService-Info.plist` (iOS)
   - `web/firebase-config.js` (Web)

### 4. Configure App Icons
Generate app icons for all platforms:
```bash
flutter pub run flutter_launcher_icons:main
```

### 5. Run the Application
```bash
# Debug mode
flutter run

# Release mode (Android)
flutter run --release

# Web
flutter run -d chrome

# Windows
flutter run -d windows
```

---

## 👥 User Roles & Access

### 🔑 Admin Access
**Role Code**: `ADMIN456`

**Capabilities:**
- Staff management (create, edit, delete)
- Office location management
- Live tracking monitoring
- Attendance history analysis
- Data export (CSV)
- Dashboard analytics

### 👤 Staff Access  
**Role Code**: `STAFF123`

**Capabilities:**
- Auto location tracking
- Manual punch in/out
- View personal attendance
- Location status monitoring
- Session history

---

## 📱 Usage Guide

### For Administrators

#### 1. **Dashboard Overview**
- View total staff count and active locations
- Monitor real-time tracking status
- Access quick management tools

#### 2. **Staff Management**
- Add new staff members with default password `Staff123`
- Assign office locations to staff
- Edit staff information
- Export staff data to CSV

#### 3. **Location Management**
- Create office locations with GPS coordinates
- Set geofence radius (default: 25 meters)
- Interactive map selection
- Manage multiple office locations

#### 4. **Live Tracking**
- Real-time staff location monitoring
- View last update timestamps
- Check staff status (inside/outside office)
- Location accuracy information

#### 5. **Attendance History**
- Comprehensive attendance reports
- Date range filtering
- Export capabilities
- Detailed session logs

### For Staff Members

#### 1. **Auto Tracking System**
- Automatic activation when entering office premises
- Location data sent every 2 minutes while in office
- 25-meter geofence accuracy
- Auto punch-out when leaving office area

#### 2. **Manual Operations**
- Manual punch in/out options
- View current location status
- Check office proximity
- Monitor tracking sessions

#### 3. **Dashboard Features**
- Today's tracking summary
- Session history
- Location accuracy indicators
- Working hours calculation

---

## 🔧 Configuration

### Environment Variables
The app uses OpenStreetMap (OSM) which doesn't require API keys

### Firebase Security Rules
```javascript
// Firestore Security Rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only access their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Admin can access all user data
    match /users/{userId} {
      allow read, write: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
    
    // Office locations readable by authenticated users
    match /officeLocations/{locationId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
  }
}
```

---

## 🎯 Features Deep Dive

### 🔍 Auto Tracking System
- **Geofencing**: 25-meter radius detection
- **Background Processing**: Continues tracking when app is backgrounded
- **Battery Optimization**: Intelligent location updates every 2 minutes
- **Accuracy Monitoring**: Real-time GPS accuracy reporting

### 📊 Analytics & Reporting
- **Daily Summaries**: Automatic daily attendance calculation
- **Working Hours**: Total time spent in office premises
- **Location Pings**: Detailed location update logs


### 🗺️ Interactive Maps
- **OpenStreetMap Integration**: High-quality open-source mapping data
- **Flutter Map Support**: Lightweight and customizable mapping solution
- **Real-time Updates**: Live location updates on maps
- **Geofence Visualization**: Visual representation of office boundaries
- **Nominatim Geocoding**: Address lookup and reverse geocoding

### 🔐 Security Features
- **Firebase Authentication**: Secure email/password authentication
- **Role-based Access Control**: Granular permission system
- **Data Encryption**: Firestore security rules
- **Session Management**: Automatic session handling

---

## 🚨 Troubleshooting

### Common Issues

#### Location Permission Denied
```bash
# Ensure location permissions are granted in device settings
# Check permission_handler configuration in pubspec.yaml
```

#### Firebase Connection Issues
```bash
# Verify firebase configuration files are in correct locations
# Check Firebase project settings and API keys
```

#### Maps Not Loading
```bash
# Verify internet connection for OpenStreetMap tile loading
# Check flutter_map configuration in pubspec.yaml
# Ensure proper tile server URLs are accessible
```

#### Build Errors
```bash
# Clean and rebuild the project
flutter clean
flutter pub get
flutter run
```

### Performance Optimization
- Enable location services for best accuracy
- Allow background app refresh for continuous tracking
- Ensure stable internet connection for real-time updates
- Grant necessary permissions for optimal functionality

---

## 🔄 Updates & Maintenance

### Regular Maintenance Tasks
1. **Firebase Rules Review**: Ensure security rules are up to date
2. **Database Cleanup**: Archive old attendance records
3. **Performance Monitoring**: Monitor app performance metrics
4. **Tile Server Monitoring**: Ensure OpenStreetMap tile servers are accessible

### Version Control
- Follow semantic versioning (MAJOR.MINOR.PATCH)
- Maintain changelog for all releases
- Test thoroughly before production deployment

---

## 🤝 Contributing

We welcome contributions to NexoTrack! Please follow these guidelines:

### Development Workflow
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Standards
- Follow Flutter/Dart style guidelines
- Add comments for complex logic
- Write unit tests for new features
- Ensure all tests pass before submitting

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 📞 Support

For support and questions:
- 📧 Email: afnnafsal@gmail.com
- 🐛 Issues: [GitHub Issues](https://github.com/afnanafsal/nexotrack/issues)
- 📖 Documentation: [Wiki](https://github.com/afnanafsal/nexotrack/wiki)

---

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Firebase for backend infrastructure
- OpenStreetMap for free and open mapping data
- Flutter Map community for the excellent mapping package
- Syncfusion for beautiful charts
- Open source community for various packages

---

<div align="center">
  <p><strong>Built with ❤️ using Flutter</strong></p>
  <p>© 2025 NexoTrack. All rights reserved.</p>
</div>

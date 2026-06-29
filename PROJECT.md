# Dhanam Store

A full-stack grocery delivery mobile application built with Flutter and FastAPI, featuring real-time order tracking, admin dashboard, and delivery management.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile App | Flutter (Dart) |
| Backend API | FastAPI (Python) |
| Database | MongoDB Atlas |
| Authentication | Firebase Auth (Phone OTP) + JWT |
| Push Notifications | Firebase Cloud Messaging |
| Hosting | Railway |
| Maps | Flutter Map + OpenStreetMap |

## Features

### Customer App
- **Phone OTP Login** — Firebase Authentication with phone number verification
- **Product Browsing** — Search, filters, categories, featured products, and flash deals
- **Shopping Cart & Checkout** — Address selection, delivery slot booking, Cash on Delivery
- **Order Tracking** — Real-time delivery tracking with map view and order timeline
- **Wishlist** — Save products for later
- **Product Reviews** — Rate and review purchased products
- **Loyalty Points & Wallet** — Earn points on purchases, digital wallet with transaction history
- **Address Management** — Save multiple delivery addresses with labels
- **Push Notifications** — Real-time order status updates

### Admin / Staff Panel
- **Dashboard** — Sales analytics, inventory stats, and order overview
- **Product Management** — CRUD operations with image uploads and bulk editing
- **Inventory Alerts** — Low-stock notifications and inventory tracking
- **Order Management** — Status updates, invoice generation, refund processing
- **Delivery Management** — Assign delivery partners, track deliveries
- **Customer Management** — View customers, manage accounts
- **Audit Logs** — Track all admin actions for accountability
- **Staff Management** — Multi-role access (admin, delivery staff)

### Backend API
- RESTful API with 50+ endpoints
- JWT-based authentication with role-based access control
- MongoDB with Motor (async driver) for high performance
- Firebase Admin SDK for push notifications
- Static file serving for product images
- CORS configuration for production security

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Flutter App    │────▶│  FastAPI Backend  │────▶│  MongoDB Atlas  │
│   (Dart)         │     │  (Python)         │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                        │
        ▼                        ▼
┌─────────────────┐     ┌──────────────────┐
│  Firebase Auth   │     │  Firebase Cloud   │
│  (Phone OTP)     │     │  Messaging (FCM)  │
└─────────────────┘     └──────────────────┘
```

## Project Structure

```
dhanam_store/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── config.dart               # API URL configuration
│   ├── models/                   # Data models (Product, Order, Address, etc.)
│   ├── screens/
│   │   ├── home_screen.dart      # Main storefront
│   │   ├── browse_screen.dart    # Product browsing & search
│   │   ├── cart_screen.dart      # Shopping cart
│   │   ├── checkout_screen.dart  # Checkout flow (Address → Slot → Review)
│   │   ├── login_screen.dart     # Phone OTP login
│   │   ├── otp_screen.dart       # OTP verification
│   │   ├── admin/                # Admin panel screens
│   │   ├── customer/             # Customer profile screens
│   │   └── order/                # Order tracking & detail screens
│   ├── services/                 # API, Auth, Cart, Order services
│   └── widgets/                  # Reusable UI components
├── backend/
│   ├── main.py                   # FastAPI app & auth endpoints
│   ├── config.py                 # Environment configuration
│   ├── database.py               # MongoDB connection & collections
│   ├── routes_orders.py          # Order CRUD & tracking
│   ├── routes_admin.py           # Admin panel endpoints
│   ├── routes_customer.py        # Customer profile endpoints
│   ├── routes_notifications.py   # Push notification endpoints
│   ├── routes_reviews.py         # Product review endpoints
│   └── push_service.py           # Firebase Cloud Messaging
└── android/                      # Android platform configuration
```

## Setup

### Prerequisites
- Flutter SDK (3.12+)
- Python 3.11+
- MongoDB Atlas account
- Firebase project with Phone Auth enabled

### Backend
```bash
cd backend
pip install -r requirements.txt
# Create .env with MONGODB_URI, JWT_SECRET, DATABASE_NAME
uvicorn main:app --reload
```

### Flutter App
```bash
flutter pub get
flutter run
```

### Production Build
```bash
flutter build appbundle --dart-define=API_URL=https://your-backend-url.com
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `MONGODB_URI` | MongoDB Atlas connection string |
| `DATABASE_NAME` | Database name (default: `dhanam_store`) |
| `JWT_SECRET` | Secret key for JWT token signing |
| `FIREBASE_CREDENTIALS` | Firebase Admin SDK credentials (JSON) |
| `CORS_ORIGINS` | Allowed origins for CORS (JSON array) |
| `DEBUG` | Enable debug mode (default: `false`) |

## Deployment

- **Backend**: Deployed on [Railway](https://railway.app) with auto-deploy from GitHub
- **Mobile App**: Android App Bundle (AAB) for Google Play Store distribution

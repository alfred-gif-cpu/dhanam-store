import 'package:flutter/material.dart';

class LegalPageScreen extends StatelessWidget {
  final String title;
  final String content;

  const LegalPageScreen({super.key, required this.title, required this.content});

  static const privacyPolicy = '''
Dhanam Store Privacy Policy
Last updated: June 2026

1. Information We Collect
We collect the following information when you use Dhanam Store:
- Phone number (for account verification and login)
- Name and email (optional, for your profile)
- Delivery addresses you save
- Order history and preferences
- Device information for push notifications

2. How We Use Your Information
- To process and deliver your orders
- To send order status updates via push notifications
- To improve our products and services
- To provide customer support

3. Data Storage & Security
- Your data is stored securely on MongoDB Atlas with encryption at rest
- Authentication is handled via Firebase with industry-standard security
- API communication uses HTTPS encryption
- We never store payment card details (Cash on Delivery only)

4. Data Sharing
We do not sell or share your personal information with third parties except:
- Delivery partners (your address and phone for order delivery)
- Firebase (for authentication and push notifications)
- As required by law

5. Your Rights
You can:
- View and update your profile information in the app
- Delete your account and all associated data
- Contact us to request a copy of your data

6. Contact Us
For privacy concerns, contact us at:
Email: support@dhanamstore.com
''';

  static const termsOfService = '''
Dhanam Store Terms of Service
Last updated: June 2026

1. Acceptance of Terms
By using the Dhanam Store app, you agree to these Terms of Service. If you do not agree, please do not use the app.

2. Account
- You must provide a valid phone number to create an account
- You are responsible for maintaining the security of your account
- You must be at least 18 years old to place orders

3. Orders & Delivery
- All orders are subject to product availability
- Delivery times are estimates and may vary
- Payment is Cash on Delivery (COD) only
- You must provide an accurate delivery address

4. Pricing
- All prices are in Indian Rupees (INR) and are inclusive of applicable GST at the rate for each product
- Delivery is free for orders above ₹499; otherwise a ₹30 delivery fee applies
- Prices may change without prior notice

5. Cancellations & Refunds
- Orders can be cancelled before they are out for delivery
- Refunds for cancelled orders will be processed within 5-7 business days
- We reserve the right to refuse refunds for delivered orders

6. User Conduct
You agree not to:
- Use the app for any unlawful purpose
- Attempt to gain unauthorized access to our systems
- Place fraudulent orders
- Abuse promotional offers

7. Limitation of Liability
Dhanam Store is provided "as is" without warranties. We are not liable for:
- Delays in delivery due to circumstances beyond our control
- Product quality issues (please report within 24 hours of delivery)
- Loss of data due to technical issues

8. Changes to Terms
We may update these terms at any time. Continued use of the app constitutes acceptance of the updated terms.

9. Contact Us
For questions about these terms, contact us at:
Email: support@dhanamstore.com
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: Text(title), centerTitle: true, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            content,
            style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF333333)),
          ),
        ),
      ),
    );
  }
}

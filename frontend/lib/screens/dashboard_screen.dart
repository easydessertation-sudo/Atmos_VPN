import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'home_screen.dart';
import 'web/web_dashboard.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Responsive(
      mobile: HomeScreen(),
      tablet: WebDashboard(), // Tablet can use web layout with adjustments
      desktop: WebDashboard(),
    );
  }
}

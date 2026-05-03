import 'package:flutter/material.dart';
import '../utils/responsive.dart';

class AppContainer extends StatelessWidget {
  final Widget child;
  final bool useMaxWidth;
  final double maxWidth;

  const AppContainer({
    super.key,
    required this.child,
    this.useMaxWidth = true,
    this.maxWidth = 1200,
  });

  @override
  Widget build(BuildContext context) {
    if (!useMaxWidth || Responsive.isMobile(context)) {
      return child;
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

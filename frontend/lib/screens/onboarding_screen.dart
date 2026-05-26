import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/design_system.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: "Protect Your Privacy",
      subtitle: "Hide your IP instantly\nBrowse anonymously anywhere",
      icon: Icons.security_rounded,
      color: AppColors.primaryBlue,
    ),
    OnboardingData(
      title: "Global Access",
      subtitle: "Unlock streaming and websites\nfrom anywhere in the world",
      icon: Icons.public_rounded,
      color: AppColors.accentPurple,
    ),
    OnboardingData(
      title: "Ultra Speed",
      subtitle: "Optimized servers for\nstreaming and gaming",
      icon: Icons.bolt_rounded,
      color: AppColors.neonCyan,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Animated Background Gradient
          Positioned.fill(
            child: AnimatedContainer(
              duration: 1.seconds,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 1.2,
                  colors: [
                    _pages[_currentPage].color.withValues(alpha: 0.15),
                    AppColors.background,
                  ],
                ),
              ),
            ),
          ),

          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return Padding(
                      padding: const EdgeInsets.all(40.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Graphic Area
                          Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: page.color.withValues(alpha: 0.1),
                              boxShadow: [
                                BoxShadow(
                                  color: page.color.withValues(alpha: 0.2),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: Icon(
                              page.icon,
                              size: 100,
                              color: page.color,
                            ),
                          )
                              .animate(key: ValueKey(index))
                              .scale(
                                  duration: 600.ms, curve: Curves.easeOutBack)
                              .moveY(
                                  begin: 10,
                                  end: -10,
                                  duration: 2.seconds,
                                  curve: Curves.easeInOut)
                              .then()
                              .moveY(
                                  begin: -10,
                                  end: 10,
                                  duration: 2.seconds,
                                  curve: Curves.easeInOut),

                          const SizedBox(height: 60),

                          // Text Content
                          Text(
                            page.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                          )
                              .animate(key: ValueKey("t$index"))
                              .fadeIn(duration: 400.ms)
                              .moveY(begin: 20, end: 0),

                          const SizedBox(height: 16),

                          Text(
                            page.subtitle,
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                          )
                              .animate(key: ValueKey("s$index"))
                              .fadeIn(delay: 200.ms)
                              .moveY(begin: 20, end: 0),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Bottom Controls
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Indicators
                    Row(
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: 300.ms,
                          margin: const EdgeInsets.only(right: 8),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: _currentPage == index
                                ? _pages[index].color
                                : AppColors.textSecondary
                                    .withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),

                    // Action Button
                    _currentPage == _pages.length - 1
                        ? ElevatedButton(
                            onPressed: () => Navigator.pushReplacementNamed(
                                context, '/login'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 32, vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ).copyWith(
                              shadowColor: WidgetStateProperty.all(
                                  AppColors.primaryBlue.withValues(alpha: 0.5)),
                              elevation: WidgetStateProperty.all(10),
                            ),
                            child: const Text("GET STARTED",
                                style: TextStyle(fontWeight: FontWeight.w800)),
                          ).animate().scale().fadeIn()
                        : IconButton(
                            onPressed: () => _pageController.nextPage(
                              duration: 500.ms,
                              curve: Curves.easeInOut,
                            ),
                            icon: const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.cardBackground,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  OnboardingData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

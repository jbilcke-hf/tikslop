// lib/widgets/ad_banner.dart
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:tikslop/config/config.dart';
import 'package:tikslop/theme/colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' if (dart.library.io) 'package:tikslop/services/html_stub.dart' as html;

class AdBanner extends StatefulWidget {
  final bool showAd;
  
  const AdBanner({
    super.key, 
    this.showAd = true,
  });

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  Map<String, String>? _currentAd;
  Timer? _rotationTimer;
  
  @override
  void initState() {
    super.initState();
    // Initialize with a random ad
    _selectRandomAd();
    // Start the rotation timer
    _startRotationTimer();
  }
  
  @override
  void dispose() {
    // Cancel the timer when the widget is disposed
    _rotationTimer?.cancel();
    super.dispose();
  }
  
  /// Starts the ad rotation timer
  void _startRotationTimer() {
    // Rotate every 30 seconds
    _rotationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _selectRandomAd();
    });
  }
  
  /// Selects a new random ad and updates the state
  void _selectRandomAd() {
    if (!mounted) return;
    
    final ads = Configuration.instance.adBanners;
    if (ads.isEmpty) {
      setState(() => _currentAd = null);
      return;
    }
    
    final random = Random();
    setState(() => _currentAd = ads[random.nextInt(ads.length)]);
  }

  /// Opens a URL in a new tab or browser
  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (kIsWeb) {
      // Use HTML for web platform
      html.window.open(url, '_blank');
    } else {
      // Use url_launcher for other platforms
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show ads if enabled in config and showAd is true
    if (!Configuration.instance.enableAds || !widget.showAd) {
      return const SizedBox.shrink();
    }

    if (_currentAd == null || _currentAd!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Divider above ad
        const Divider(color: TikSlopColors.surfaceVariant),
        
        // Ad banner
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: InkWell(
            onTap: () => _launchURL(_currentAd!['link'] ?? ''),
            child: Image.asset(
              _currentAd!['image'] ?? '',
              height: 80,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // If image fails to load, show a placeholder
                print('Error loading ad image: $error');
                return Container(
                  height: 80,
                  color: Colors.grey.withOpacity(0.1),
                  child: const Center(child: Text('Ad')),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
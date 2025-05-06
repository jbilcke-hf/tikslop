// lib/widgets/ai_content_disclaimer.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

class AiContentDisclaimer extends StatelessWidget {
  final bool isInteractive;
  final bool compact;
  
  const AiContentDisclaimer({
    super.key,
    this.isInteractive = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactDisclaimer(context);
    }
    return _buildFullDisclaimer(context);
  }
  
  Widget _buildCompactDisclaimer(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF047857), // emerald-700
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final baseSize = constraints.maxWidth / 20;
            final iconSize = baseSize * 1.5;
            
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  color: Colors.white,
                  size: iconSize,
                ),
                const SizedBox(height: 8),
                Text(
                  'AI Content',
                  style: GoogleFonts.arimo(
                    fontSize: baseSize,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    shadows: const [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 2.0,
                        color: Color.fromRGBO(0, 0, 0, 0.3),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFullDisclaimer(BuildContext context) {    
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF047857), // emerald-700
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Scale text based on container width
            final baseSize = constraints.maxWidth / 25;
            final smallTextSize = baseSize * 0.7;
            final mediumTextSize = baseSize;
            final largeTextSize = baseSize * 1.3;
            
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'The following ',
                        style: GoogleFonts.arimo(
                          fontSize: smallTextSize,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                          height: 1.0,
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 3.0,
                              color: Color.fromRGBO(0, 0, 0, 0.3),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'content',
                        style: GoogleFonts.arimo(
                          fontSize: mediumTextSize,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          height: 1.0,
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 3.0,
                              color: Color.fromRGBO(0, 0, 0, 0.3),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        isInteractive ? ' will be ' : ' has been ',
                        style: GoogleFonts.arimo(
                          fontSize: smallTextSize,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                          height: 1.0,
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 3.0,
                              color: Color.fromRGBO(0, 0, 0, 0.3),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'synthesized',
                        style: GoogleFonts.arimo(
                          fontSize: mediumTextSize,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          height: 1.0,
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 3.0,
                              color: Color.fromRGBO(0, 0, 0, 0.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'using',
                        style: GoogleFonts.arimo(
                          fontSize: smallTextSize,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                          height: 1.0,
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 3.0,
                              color: Color.fromRGBO(0, 0, 0, 0.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'artificial intelligence',
                    style: GoogleFonts.arimo(
                      fontSize: largeTextSize,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      height: 1.0,
                      shadows: const [
                        Shadow(
                          offset: Offset(0, 2),
                          blurRadius: 3.0,
                          color: Color.fromRGBO(0, 0, 0, 0.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'and may contain hallucinations or factual inaccuracies.',
                    style: GoogleFonts.arimo(
                      fontSize: smallTextSize,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                      height: 1.0,
                      shadows: const [
                        Shadow(
                          offset: Offset(0, 2),
                          blurRadius: 3.0,
                          color: Color.fromRGBO(0, 0, 0, 0.3),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

import '../theme.dart';

/// Noctorium's mark: the same picture as the launcher icon, the desktop's window and the installers.
///
/// The picture's own background is black, as Night's page is, so it is given a hairline edge: without one,
/// the figure floats on the page with nothing to say where the tile ends.
class Mark extends StatelessWidget {
  const Mark({super.key, required this.size, this.glow = false});

  final double size;

  /// A soft violet light behind it, for where it stands alone at the top of a page.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * .26);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: Night.page,
        border: Border.all(
          color: Night.accent.withValues(alpha: glow ? .45 : .32),
          width: size >= 64 ? 1.5 : 1,
        ),
        boxShadow: [if (glow) BoxShadow(color: Night.accent.withValues(alpha: .30), blurRadius: size * .6)],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          'assets/noctorium.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Noctorium',
          // Never a broken-image box where the mark should be: the black it sits on is the next best thing.
          errorBuilder: (context, error, stack) => const SizedBox.expand(),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Responsive layout breakpoints and helpers for tablet/iPad support.
class ResponsiveLayout {
  ResponsiveLayout._();

  /// Breakpoints
  static const double mobileWidth = 600;
  static const double tabletWidth = 900;
  static const double desktopWidth = 1200;

  /// Whether the current screen is mobile-sized (< 600px).
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileWidth;

  /// Whether the current screen is tablet-sized (600-900px).
  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= mobileWidth && w < desktopWidth;
  }

  /// Whether the current screen is desktop-sized (>= 1200px).
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopWidth;

  /// Whether to use two-column layout (tablet/desktop).
  static bool useTwoColumn(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletWidth;

  /// Grid column count based on screen width.
  static int gridColumns(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopWidth) return 4;
    if (w >= tabletWidth) return 3;
    if (w >= mobileWidth) return 2;
    return 1;
  }

  /// Content max width for readability on large screens.
  static double contentMaxWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopWidth) return 800;
    if (w >= tabletWidth) return 700;
    return double.infinity;
  }

  /// Side panel width for master-detail layouts on tablet.
  static double sidePanelWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopWidth) return 360;
    if (w >= tabletWidth) return 320;
    return w;
  }

  /// Padding based on screen size.
  static EdgeInsets screenPadding(BuildContext context) {
    if (isDesktop(context))
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    if (isTablet(context))
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  }
}

/// Widget that shows different layouts based on screen size.
/// On tablet/desktop: master-detail with side panel.
/// On mobile: single column with navigation.
class ResponsiveMasterDetail extends StatelessWidget {
  const ResponsiveMasterDetail({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth,
  });

  final Widget master;
  final Widget detail;
  final double? masterWidth;

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveLayout.useTwoColumn(context)) {
      return master;
    }

    final width = masterWidth ?? ResponsiveLayout.sidePanelWidth(context);

    return Row(
      children: [
        SizedBox(width: width, child: master),
        const VerticalDivider(width: 1),
        Expanded(child: detail),
      ],
    );
  }
}

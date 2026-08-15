import 'package:flutter/widgets.dart';

enum AppBreakpoint { mobile, tablet, desktop, largeDesktop }

class AppBreakpoints {
  const AppBreakpoints._();

  static const mobile = 600.0;
  static const tablet = 1024.0;
  static const desktop = 1440.0;

  static AppBreakpoint fromWidth(double width) {
    if (width < mobile) {
      return AppBreakpoint.mobile;
    }
    if (width < tablet) {
      return AppBreakpoint.tablet;
    }
    if (width < desktop) {
      return AppBreakpoint.desktop;
    }
    return AppBreakpoint.largeDesktop;
  }

  static AppBreakpoint of(BuildContext context) {
    return fromWidth(MediaQuery.sizeOf(context).width);
  }

  static bool isMobileWidth(double width) => width < mobile;

  static bool isTabletWidth(double width) => width >= mobile && width < tablet;

  static bool isDesktopWidth(double width) => width >= tablet;

  static bool isLargeDesktopWidth(double width) => width >= desktop;

  static bool isMobile(BuildContext context) {
    return isMobileWidth(MediaQuery.sizeOf(context).width);
  }

  static bool isTablet(BuildContext context) {
    return isTabletWidth(MediaQuery.sizeOf(context).width);
  }

  static bool isDesktop(BuildContext context) {
    return isDesktopWidth(MediaQuery.sizeOf(context).width);
  }

  static bool isLargeDesktop(BuildContext context) {
    return isLargeDesktopWidth(MediaQuery.sizeOf(context).width);
  }

  static bool isCompactDesktop(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= tablet && width < desktop;
  }

  static double adminSidebarWidth(BuildContext context) {
    return isLargeDesktop(context) ? 244 : 88;
  }

  static double screenPadding(BuildContext context) {
    return isMobile(context) ? 16 : 32;
  }
}

import 'package:flutter/widgets.dart';
import 'package:app_admin_staff/design_system/tokens/app_breakpoints.dart';

class Breakpoints {
  static const mobile = AppBreakpoints.mobile;
  static const tablet = AppBreakpoints.tablet;
  static const desktop = AppBreakpoints.desktop;

  static bool isMobile(BuildContext context) {
    return AppBreakpoints.isMobile(context);
  }

  static bool isTablet(BuildContext context) {
    return AppBreakpoints.isTablet(context);
  }

  static bool isDesktop(BuildContext context) {
    return AppBreakpoints.isDesktop(context);
  }

  static bool isLargeDesktop(BuildContext context) {
    return AppBreakpoints.isLargeDesktop(context);
  }

  static bool isCompactDesktop(BuildContext context) {
    return AppBreakpoints.isCompactDesktop(context);
  }

  static AppBreakpoint of(BuildContext context) {
    return AppBreakpoints.of(context);
  }
}

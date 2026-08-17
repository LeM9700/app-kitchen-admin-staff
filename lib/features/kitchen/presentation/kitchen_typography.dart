import 'package:flutter/material.dart';

class KitchenTypography {
  const KitchenTypography._();

  static TextStyle headerTitle(BuildContext context) {
    return Theme.of(context).textTheme.headlineSmall!.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        );
  }

  static TextStyle headerCounter(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        );
  }

  static TextStyle ticketNumber(BuildContext context, {bool compact = false}) {
    return Theme.of(context).textTheme.titleLarge!.copyWith(
          fontSize: compact ? 16 : 19,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        );
  }

  static TextStyle ticketStatus(BuildContext context, {bool compact = false}) {
    return Theme.of(context).textTheme.labelLarge!.copyWith(
          fontSize: compact ? 11 : 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        );
  }

  static TextStyle timer(BuildContext context, {bool compact = false}) {
    return Theme.of(context).textTheme.titleLarge!.copyWith(
          fontSize: compact ? 18 : 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        );
  }

  static TextStyle product(BuildContext context, {bool compact = false}) {
    return Theme.of(context).textTheme.titleLarge!.copyWith(
          fontSize: compact ? 17 : 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
          height: 1.12,
        );
  }

  static TextStyle variant(BuildContext context, {bool compact = false}) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
          fontSize: compact ? 13 : 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          height: 1.15,
        );
  }

  static TextStyle extra(BuildContext context, {bool compact = false}) {
    return Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontSize: compact ? 13 : 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.18,
        );
  }

  static TextStyle meta(BuildContext context) {
    return Theme.of(context).textTheme.labelLarge!.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        );
  }
}

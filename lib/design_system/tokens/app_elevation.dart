import 'package:flutter/material.dart';

class AppElevation {
  const AppElevation._();

  static const none = <BoxShadow>[];
  static const subtle = [
    BoxShadow(
      color: Color(0x0F0E121A),
      offset: Offset(0, 8),
      blurRadius: 18,
    ),
  ];
}

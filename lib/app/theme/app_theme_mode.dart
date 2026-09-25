import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appThemeModeProvider = StateProvider<ThemeMode>(
  (ref) => ThemeMode.light,
);

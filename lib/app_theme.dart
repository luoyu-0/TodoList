import 'dart:io';

import 'package:flutter/material.dart';

ThemeData buildAppTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5)),
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFFF8FAFC),
  fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : null,
);

import 'package:flutter/material.dart';

Color colorFromHex(String? hex, {Color fallback = Colors.grey}) {
  if (hex == null) return fallback;

  final clean = hex.replaceAll('#', '').trim();
  if (clean.length != 6) return fallback;

  try {
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return fallback;
  }
}
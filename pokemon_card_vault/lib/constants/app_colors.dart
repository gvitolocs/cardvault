import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFF2E7D32); // Pokemon Green
  static const Color secondary = Color(0xFF4CAF50); // Light Green
  static const Color accent = Color(0xFFFF6F00); // Orange
  
  // Background Colors
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color cardBackground = Colors.white;
  
  // Text Colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFFBDBDBD);
  
  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);
  
  // Pokemon Type Colors
  static const Color fire = Color(0xFFFF5722);
  static const Color water = Color(0xFF2196F3);
  static const Color lightning = Color(0xFFFFEB3B);
  static const Color grass = Color(0xFF4CAF50);
  static const Color psychic = Color(0xFF9C27B0);
  static const Color fighting = Color(0xFF795548);
  static const Color darkness = Color(0xFF424242);
  static const Color metal = Color(0xFF607D8B);
  static const Color fairy = Color(0xFFE91E63);
  static const Color dragon = Color(0xFF3F51B5);
  static const Color colorless = Color(0xFF9E9E9E);
  
  // Rarity Colors
  static const Color common = Color(0xFF9E9E9E);
  static const Color uncommon = Color(0xFF4CAF50);
  static const Color rare = Color(0xFF2196F3);
  static const Color rareHolo = Color(0xFF9C27B0);
  
  // Gradient Colors
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );
  
  static const LinearGradient fireGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF5722), Color(0xFFFF9800)],
  );
  
  static const LinearGradient waterGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2196F3), Color(0xFF03A9F4)],
  );
  
  static const LinearGradient lightningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFEB3B), Color(0xFFFFC107)],
  );
  
  static const LinearGradient grassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4CAF50), Color(0xFF8BC34A)],
  );
}

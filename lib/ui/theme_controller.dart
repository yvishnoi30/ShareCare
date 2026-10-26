import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's light/dark choice and remembers it between launches.
///
/// Until the user picks a theme, the app follows the device setting.
/// Changing the theme only rebuilds the widgets that depend on it; it never
/// touches file selections, sender state or transfers.
class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initialMode = ThemeMode.system})
      : _mode = initialMode;

  static const String _preferenceKey = 'sharecare_theme_mode';

  ThemeMode _mode;
  bool _disposed = false;

  ThemeMode get mode => _mode;

  /// Loads the saved choice. If nothing is saved, or storage is not
  /// available, the current mode is kept.
  Future<void> restore() async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final String? stored = preferences.getString(_preferenceKey);

      ThemeMode restored = ThemeMode.system;
      if (stored == 'light') {
        restored = ThemeMode.light;
      } else if (stored == 'dark') {
        restored = ThemeMode.dark;
      }

      if (restored != _mode && !_disposed) {
        _mode = restored;
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable: keep the current mode.
    }
  }

  /// Applies [mode] immediately and saves it in the background.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;

    _mode = mode;
    notifyListeners();

    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      String value = 'system';
      if (mode == ThemeMode.light) {
        value = 'light';
      } else if (mode == ThemeMode.dark) {
        value = 'dark';
      }

      await preferences.setString(_preferenceKey, value);
    } catch (_) {
      // The theme still changes for this session if saving fails.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Makes the [ThemeController] available to every screen.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final ThemeScope? scope =
        context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope found above this context.');
    return scope!.notifier!;
  }
}

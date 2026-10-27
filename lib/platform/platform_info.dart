
import 'dart:io';

/// Desktop platforms use desktop-specific screens and file saving.
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

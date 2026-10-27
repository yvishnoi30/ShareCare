
import 'android_file_saver.dart';
import 'file_saver.dart';
import 'platform_info.dart';
import 'windows_file_saver.dart';

/// Chooses the correct file-saving implementation for this platform.
FileSaver createFileSaver() {
  if (isDesktopPlatform) {
    return WindowsFileSaver();
  }

  return AndroidFileSaver();
}

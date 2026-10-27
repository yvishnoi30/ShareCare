
import 'package:flutter/material.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';

  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

IconData iconForFile(String name) {
  final String lower = name.toLowerCase();

  if ([
    '.jpg', '.jpeg', '.png', '.webp', '.gif',
    '.bmp', '.heic', '.heif', '.tif', '.tiff', '.svg'
  ].any(lower.endsWith)) {
    return Icons.image_outlined;
  }

  if ([
    '.mp4', '.mov', '.mkv', '.avi', '.webm',
    '.3gp', '.mpeg', '.mpg', '.wmv', '.m4v'
  ].any(lower.endsWith)) {
    return Icons.video_file_outlined;
  }

  if ([
    '.mp3', '.wav', '.aac', '.m4a', '.flac', '.ogg', '.opus'
  ].any(lower.endsWith)) {
    return Icons.audio_file_outlined;
  }

  if (lower.endsWith('.pdf')) {
    return Icons.picture_as_pdf_outlined;
  }

  if (lower.endsWith('.apk')) {
    return Icons.android_outlined;
  }

  if ([
    '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2'
  ].any(lower.endsWith)) {
    return Icons.folder_zip_outlined;
  }

  if ([
    '.doc', '.docx', '.odt', '.rtf'
  ].any(lower.endsWith)) {
    return Icons.description_outlined;
  }

  if ([
    '.xls', '.xlsx', '.csv', '.ods'
  ].any(lower.endsWith)) {
    return Icons.table_chart_outlined;
  }

  if ([
    '.ppt', '.pptx', '.odp'
  ].any(lower.endsWith)) {
    return Icons.slideshow_outlined;
  }

  if ([
    '.txt', '.md', '.json', '.xml', '.html', '.css',
    '.js', '.dart', '.java', '.py', '.kt', '.c', '.cpp', '.h'
  ].any(lower.endsWith)) {
    return Icons.code_outlined;
  }

  return Icons.insert_drive_file_outlined;
}

final RegExp _windowsReservedName = RegExp(
  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$',
  caseSensitive: false,
);

String safeReceivedFileName(String originalName) {
  String cleaned = originalName
      .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1F]'), '_')
      .trim();

  cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');

  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
    return 'shared_file';
  }

  if (_windowsReservedName.hasMatch(cleaned)) {
    cleaned = '_$cleaned';
  }

  return cleaned;
}

/// Attempt 0 keeps the original name.
/// Later attempts add a number before the extension.
String numberedFileName(String name, int attempt) {
  if (attempt <= 0) return name;

  final int dot = name.lastIndexOf('.');

  if (dot <= 0 || dot == name.length - 1) {
    return '$name ($attempt)';
  }

  return '${name.substring(0, dot)} ($attempt)${name.substring(dot)}';
}

String mimeTypeForFile(String name) {
  const Map<String, String> mimeTypes = <String, String>{
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'zip': 'application/zip',
    'apk': 'application/vnd.android.package-archive',
  };

  final int dot = name.lastIndexOf('.');

  if (dot <= 0 || dot == name.length - 1) {
    return 'application/octet-stream';
  }

  return mimeTypes[name.substring(dot + 1).toLowerCase()] ??
      'application/octet-stream';
}

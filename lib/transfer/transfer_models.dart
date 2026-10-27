
import 'dart:convert';
import 'dart:io';

/// An error that is safe to show to the user as-is.
class TransferException implements Exception {
  const TransferException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Thrown when the user cancels a running download.
class TransferCancelledException extends TransferException {
  const TransferCancelledException()
      : super('The transfer was cancelled.');
}

/// One entry of the sender's /files list.
class ReceivedFile {
  const ReceivedFile({
    required this.id,
    required this.name,
    required this.size,
  });

  final String id;
  final String name;
  final int size;

  factory ReceivedFile.fromJson(Map<String, dynamic> json) {
    return ReceivedFile(
      id: json['id'] as String,
      name: json['name'] as String,
      size: (json['size'] as num).toInt(),
    );
  }
}

/// Connection information shared between Android and Windows.
///
/// Keep this format compatible with the existing Android QR scanner.
class PairingInfo {
  const PairingInfo({
    required this.host,
    required this.port,
    required this.token,
  });

  final String host;
  final int port;
  final String token;

  static const String appName = 'ShareCare';
  static const int protocolVersion = 1;

  String toPayload() {
    return jsonEncode(<String, Object>{
      'app': appName,
      'version': protocolVersion,
      'host': host,
      'port': port,
      'token': token,
    });
  }

  factory PairingInfo.fromPayload(String raw) {
    dynamic decoded;

    try {
      decoded = jsonDecode(raw.trim());
    } on FormatException {
      throw const TransferException(
        'That is not a ShareCare pairing code. '
        'Copy the whole code from the sending device.',
      );
    }

    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != appName ||
        decoded['version'] != protocolVersion ||
        decoded['host'] is! String ||
        decoded['port'] is! int ||
        decoded['token'] is! String) {
      throw const TransferException('Invalid ShareCare QR code.');
    }

    final String host = decoded['host'] as String;
    final int port = decoded['port'] as int;
    final String token = decoded['token'] as String;

    if (host.isEmpty ||
        port < 1 ||
        port > 65535 ||
        token.isEmpty) {
      throw const TransferException(
        'Invalid connection details.',
      );
    }

    return PairingInfo(
      host: host,
      port: port,
      token: token,
    );
  }

  factory PairingInfo.fromFields({
    required String host,
    required String port,
    required String token,
  }) {
    final String? error =
        validateHost(host) ??
        validatePort(port) ??
        validateToken(token);

    if (error != null) {
      throw TransferException(error);
    }

    return PairingInfo(
      host: host.trim(),
      port: int.parse(port.trim()),
      token: token.trim(),
    );
  }

  static String? validateHost(String? value) {
    final String text = (value ?? '').trim();

    if (text.isEmpty) {
      return 'Enter the sender address, for example 192.168.1.20.';
    }

    final InternetAddress? parsed = InternetAddress.tryParse(text);

    if (parsed == null ||
        parsed.type != InternetAddressType.IPv4) {
      return 'Enter a valid IPv4 address, for example 192.168.1.20.';
    }

    return null;
  }

  static String? validatePort(String? value) {
    final String text = (value ?? '').trim();

    if (text.isEmpty) {
      return 'Enter the port shown on the sending device.';
    }

    final int? port = int.tryParse(text);

    if (port == null || port < 1 || port > 65535) {
      return 'The port must be a number from 1 to 65535.';
    }

    return null;
  }

  static String? validateToken(String? value) {
    final String text = (value ?? '').trim();

    if (text.isEmpty) {
      return 'Enter the session token shown on the sending device.';
    }

    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text)) {
      return 'The token may only contain letters, numbers, - and _.';
    }

    return null;
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform/src/models/printer_device.dart';
import 'package:flutter_pos_printer_platform/discovery.dart';
import 'package:flutter_pos_printer_platform/printer.dart';
import 'package:ping_discover_network/ping_discover_network.dart';

import '../helpers/printer_status_checker.dart';

class TcpPrinterInput extends BasePrinterInput {
  final String ipAddress;
  final int port;
  final Duration timeout;
  final Duration retryInterval;
  final int maxRetries;

  TcpPrinterInput({
    required this.ipAddress,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
    this.retryInterval = const Duration(seconds: 1),
    this.maxRetries = 3,
  });
}

class TcpPrinterInfo {
  String address;

  TcpPrinterInfo({
    required this.address,
  });
}

class TcpPrinterConnector implements PrinterConnector<TcpPrinterInput> {
  TcpPrinterConnector._();

  static final TcpPrinterConnector _instance = TcpPrinterConnector._();

  static TcpPrinterConnector get instance => _instance;

  String? _host;
  int? _port;
  Socket? _socket;
  TCPStatus _status = TCPStatus.none;

  final StreamController<TCPStatus> _statusStreamController = StreamController.broadcast();

  Stream<TCPStatus> get _statusStream => _statusStreamController.stream;

  TCPStatus get status => _status;

  set status(TCPStatus newStatus) {
    _status = newStatus;
    _statusStreamController.add(newStatus);
  }

  bool get isConnected => _socket != null && status == TCPStatus.connected;

  // to track printers that are having issues
  final Map<String, DateTime> _problematicPrinters = {};

  static Function(String message, {String? level, dynamic error, StackTrace? stackTrace})? logCallback;

  static void _log(String message, {String level = 'info', dynamic error, StackTrace? stackTrace}) {
    if (level == 'error') {
      debugPrint('ERROR: $message');
      if (error != null) debugPrint('Error details: $error');
    } else {
      debugPrint(message);
    }

    // Send to callback if available
    if (logCallback != null) {
      logCallback!(message, level: level, error: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<PrinterConnectStatusResult> connect(TcpPrinterInput model) async {
    int retryCount = 0;
    SocketException? lastException;
    StackTrace? lastStackTrace;

    // Clear any existing socket first
    await _safeCloseSocket();

    // Add check for recent failures to avoid rapid reconnection attempts
    String printerKey = '${model.ipAddress}:${model.port}';
    if (_problematicPrinters.containsKey(printerKey)) {
      DateTime lastFailure = _problematicPrinters[printerKey]!;
      if (DateTime.now().difference(lastFailure) < Duration(seconds: 10)) {
        // Wait longer for problematic printers to recover
        await Future.delayed(Duration(seconds: 1));
      }
    }

    while (retryCount < model.maxRetries) {
      try {
        _socket = await Socket.connect(
          model.ipAddress,
          model.port,
          timeout: model.timeout,
        );

        _host = model.ipAddress;
        _port = model.port;
        status = TCPStatus.connected;

        // On successful connection, remove from problematic printers
        _problematicPrinters.remove(printerKey);

        // Add a small delay after connecting to ensure printer is ready
        await Future.delayed(Duration(milliseconds: 100));

        return PrinterConnectStatusResult(isSuccess: true);
      } on SocketException catch (e, stackTrace) {
        lastException = e;
        lastStackTrace = stackTrace;
        _log('Connection attempt ${retryCount + 1} failed: ${e.message}');

        // Add to problematic printers list
        _problematicPrinters[printerKey] = DateTime.now();

        if (retryCount < model.maxRetries - 1) {
          // Increasing delays between retries (1s, 2s, 4s)
          await Future.delayed(Duration(milliseconds: 1000 * (1 << retryCount)));
        }
        retryCount++;
      } catch (e, stackTrace) {
        _log('Unexpected error during connect: $e');
        _problematicPrinters[printerKey] = DateTime.now();
        status = TCPStatus.none;
        return PrinterConnectStatusResult(
          isSuccess: false,
          exception: 'Unexpected error: $e',
          stackTrace: stackTrace,
        );
      }
    }

    status = TCPStatus.none;
    return PrinterConnectStatusResult(
      isSuccess: false,
      exception: '${model.ipAddress}:${model.port}: ${lastException}',
      stackTrace: lastStackTrace,
    );
  }

  @override
  Future<PrinterConnectStatusResult> send(List<int> bytes, [TcpPrinterInput? model]) async {
    if (!isConnected) {
      if (model != null) {
        final connectResult = await connect(model);
        if (!connectResult.isSuccess) {
          return connectResult;
        }
      } else {
        return PrinterConnectStatusResult(
          isSuccess: false,
          exception: 'Not connected and no connection details provided',
        );
      }
    }

    try {
      _socket!.add(Uint8List.fromList(bytes));
      await _socket!.flush();
      return PrinterConnectStatusResult(isSuccess: true);
    } catch (e, stackTrace) {
      status = TCPStatus.none;
      return PrinterConnectStatusResult(
        isSuccess: false,
        exception: 'Send error: $e',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<PrinterConnectStatusResult> sendWithRetries(List<int> bytes, [TcpPrinterInput? model]) async {
    if (!isConnected) {
      if (model != null) {
        final connectResult = await connect(model);
        if (!connectResult.isSuccess) {
          return connectResult;
        }
        await Future.delayed(Duration(milliseconds: 100));
      } else {
        return PrinterConnectStatusResult(
          isSuccess: false,
          exception: 'Not connected and no connection details provided',
        );
      }
    }

    int retryCount = 0;
    const int maxRetries = 3;
    const Duration retryDelay = Duration(milliseconds: 500);
    SocketException? lastException;
    StackTrace? lastStackTrace;

    while (retryCount < maxRetries) {
      try {
        // Check printer status
        String printerKey = '${model?.ipAddress}:9100';
        bool printerReady = await PrinterStatusChecker.checkStatus(
          _socket!, printerKey,
          maxRetries: 2, // Less retries for status check within send retry loop
          retryDelay: Duration(milliseconds: 200),
        );

        if (!printerReady) {
          throw SocketException('Printer not ready or in error state');
        }

        // Send data
        _socket!.add(Uint8List.fromList(bytes));
        await _socket!.flush();

        return PrinterConnectStatusResult(isSuccess: true);
      } catch (e, stackTrace) {
        lastException = e is SocketException ? e : SocketException(e.toString());
        lastStackTrace = stackTrace;

        _log('Print attempt ${retryCount + 1} failed: $e');

        retryCount++;
        if (retryCount < maxRetries) {
          await Future.delayed(retryDelay);

          // Try to reconnect if needed
          if (!isConnected && model != null) {
            final reconnectResult = await connect(model);
            if (!reconnectResult.isSuccess) {
              continue;
            }
          }
        }
      }
    }

    status = TCPStatus.none;
    return PrinterConnectStatusResult(
      isSuccess: false,
      exception: 'Send error after $maxRetries attempts: ${lastException?.message}',
      stackTrace: lastStackTrace,
    );
  }

  @override
  Future<PrinterConnectStatusResult> splitSend(List<List<int>> bytes,
      {TcpPrinterInput? model, int delayBetweenMs = 50}) async {
    _log(
        'splitSend ${bytes.length} sections to print, total size: ${bytes.fold(0, (sum, item) => sum + item.length)} bytes',
        level: 'warn');

    // Ensure properly connected
    if (!isConnected) {
      if (model != null) {
        final connectResult = await connect(model);
        if (!connectResult.isSuccess) {
          return connectResult;
        }
      } else {
        return PrinterConnectStatusResult(
          isSuccess: false,
          exception: 'Not connected and no connection details provided',
        );
      }
    }

    try {
      if (_socket == null) {
        throw SocketException('Socket is null');
      }

      // Set important socket options for printer communication
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      // Calculate adaptive delays based on data size
      int totalSize = bytes.fold(0, (sum, section) => sum + section.length);
      int sectionCount = bytes.length;

      // Calculate optimal delay between chunks (larger sections need more time)
      int adaptiveDelay = delayBetweenMs;
      if (sectionCount > 10) {
        adaptiveDelay = delayBetweenMs + 30;
      } else if (totalSize > 50000) {
        adaptiveDelay = delayBetweenMs + 20;
      }

      _log('Starting split send with ${bytes.length} sections, total size: $totalSize bytes, delay: $adaptiveDelay ms');

      // More conservative flushing strategy
      for (int i = 0; i < bytes.length; i++) {
        final section = bytes[i];
        if (section.isEmpty) continue;

        // Send data in smaller chunks if section is large
        if (section.length > 8192) {
          // Break large sections into chunks of 4KB
          final chunks = _splitIntoChunks(section, 4096);
          for (final chunk in chunks) {
            _socket!.add(Uint8List.fromList(chunk));
            _log('Sent print chunk ${i + 1}/${bytes.length}, chunk size: ${bytes[i].length} bytes', level: 'info');

            await _socket!.flush().timeout(Duration(seconds: 5), onTimeout: () {
              throw TimeoutException('Flush operation timed out - printer may be busy');
            });
            await Future.delayed(Duration(milliseconds: 20));
          }
        } else {
          // Small enough section to send at once
          _socket!.add(Uint8List.fromList(section));
          _log('Sent small section print ${i + 1}/${bytes.length}, section size: ${bytes[i].length} bytes',
              level: 'info');

          // Flush more frequently: always flush after each section
          await _socket!.flush().timeout(Duration(seconds: 3), onTimeout: () {
            throw TimeoutException('Flush operation timed out - printer may be busy');
          });
        }

        // Add delay between sections
        if (i < bytes.length - 1) {
          // Use adaptive delay based on section size
          int currentDelay = adaptiveDelay;
          if (section.length > 4096) {
            currentDelay += 20; // Additional delay for larger sections
          }
          await Future.delayed(Duration(milliseconds: currentDelay));
        }
      }

      // Give printer time to process before returning
      await Future.delayed(Duration(milliseconds: 200));

      _log('Successfully sent all ${bytes.length} print sections', level: 'warn');
      return PrinterConnectStatusResult(isSuccess: true);
    } catch (e, stackTrace) {
      _log('Failed to splitSend print job: $e', level: 'error', error: stackTrace);

      // Record printer issues
      if (model != null) {
        String printerKey = '${model.ipAddress}:${model.port}';
        _problematicPrinters[printerKey] = DateTime.now();
      }

      status = TCPStatus.none;
      await _safeCloseSocket();
      return PrinterConnectStatusResult(
        isSuccess: false,
        exception: 'Split send error: $e',
        stackTrace: stackTrace,
      );
    }
  }

  // Helper to split large chunks
  List<List<int>> _splitIntoChunks(List<int> source, int chunkSize) {
    List<List<int>> result = [];
    for (var i = 0; i < source.length; i += chunkSize) {
      var end = (i + chunkSize < source.length) ? i + chunkSize : source.length;
      result.add(source.sublist(i, end));
    }
    return result;
  }

  // Improve the safe close method
  Future<void> _safeCloseSocket() async {
    if (_socket != null) {
      try {
        // Wait for any pending writes to complete
        await _socket!.flush().timeout(Duration(seconds: 1), onTimeout: () => null);

        // Close normally
        await _socket!.close().timeout(Duration(seconds: 1), onTimeout: () => null);

        // Destroy the socket
        _socket!.destroy();
        _socket = null;
      } catch (e) {
        _log('Error closing socket: $e');

        // Destroy in case of error
        _socket?.destroy();
        _socket = null;
      }
    }
  }

  @override
  Future<bool> disconnect({int? delayMs}) async {
    try {
      // Wait before closing to allow queued commands to complete
      if (delayMs != null && delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      await _safeCloseSocket();
      status = TCPStatus.none;
      return true;
    } catch (e) {
      _log('Error during disconnect: $e');
      status = TCPStatus.none;
      return false;
    }
  }

  static Future<List<PrinterDiscovered<TcpPrinterInfo>>> discoverPrinters({
    required String ipAddress,
    int? port,
    Duration? timeOut,
  }) async {
    final List<PrinterDiscovered<TcpPrinterInfo>> result = [];

    if (ipAddress.isEmpty) {
      return result;
    }

    try {
      final String subnet = ipAddress.substring(0, ipAddress.lastIndexOf('.'));
      final stream = NetworkScanner(
        subnet: subnet,
        port: port ?? 9100,
        timeout: timeOut ?? const Duration(milliseconds: 4000),
      ).discover();

      await for (var addr in stream) {
        if (addr.exists) {
          result.add(PrinterDiscovered<TcpPrinterInfo>(
            name: "${addr.ip}:${port ?? 9100}",
            detail: TcpPrinterInfo(address: addr.ip),
          ));
        }
      }
    } catch (e) {
      _log('Error during printer discovery: $e');
    }

    return result;
  }

  Stream<PrinterDevice> discovery({required TcpPrinterInput? model}) async* {
    if (model?.ipAddress == null || model!.ipAddress.isEmpty) {
      _log('Invalid IP address provided');
      return;
    }

    try {
      final String subnet = model.ipAddress.substring(0, model.ipAddress.lastIndexOf('.'));
      final stream = NetworkScanner(
        subnet: subnet,
        port: model.port,
        timeout: model.timeout,
      ).discover();

      await for (var data in stream) {
        if (data.exists) {
          yield PrinterDevice(
            name: "${data.ip}:${model.port}",
            address: data.ip,
          );
        }
      }
    } catch (e) {
      _log('Error during printer discovery: $e');
    }
  }

  Stream<TCPStatus> get currentStatus async* {
    yield status;
    yield* _statusStream;
  }

  // Clean up resources
  void dispose() {
    _safeCloseSocket();
    _statusStreamController.close();
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dart_ping/dart_ping.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform/src/models/printer_device.dart';
import 'package:flutter_pos_printer_platform/discovery.dart';
import 'package:flutter_pos_printer_platform/printer.dart';
import 'package:ping_discover_network_forked/ping_discover_network_forked.dart';

class TcpPrinterInput extends BasePrinterInput {
  final String ipAddress;
  final int port;
  final Duration timeout;

  TcpPrinterInput({
    required this.ipAddress,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
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

  static TcpPrinterConnector _instance = TcpPrinterConnector._();

  static TcpPrinterConnector get instance => _instance;

  TcpPrinterConnector();

  String? _host;
  int? _port;
  Socket? _socket;
  TCPStatus status = TCPStatus.none;

  Stream<TCPStatus> get _statusStream => _statusStreamController.stream;
  final StreamController<TCPStatus> _statusStreamController = StreamController.broadcast();

  static Future<List<PrinterDiscovered<TcpPrinterInfo>>> discoverPrinters(
      {required String ipAddress, int? port, Duration? timeOut}) async {
    final List<PrinterDiscovered<TcpPrinterInfo>> result = [];
    final defaultPort = port ?? 9100;

    String deviceIp = ipAddress;
    final String subnet = deviceIp.substring(0, deviceIp.lastIndexOf('.'));
    // final List<String> ips = List.generate(255, (index) => '$subnet.$index');

    final stream = NetworkAnalyzer.discover2(
      subnet,
      defaultPort,
      timeout: timeOut ?? Duration(milliseconds: 4000),
    );

    await for (var addr in stream) {
      if (addr.exists) {
        result.add(PrinterDiscovered<TcpPrinterInfo>(
            name: "${addr.ip}:$defaultPort", detail: TcpPrinterInfo(address: addr.ip)));
      }
    }

    return result;
  }

  /// Starts a scan for network printers.
  Stream<PrinterDevice> discovery({required TcpPrinterInput? model}) async* {
    final defaultPort = model?.port ?? 9100;

    String? deviceIp = model?.ipAddress;

    final String subnet = deviceIp!.substring(0, deviceIp.lastIndexOf('.'));

    final stream = NetworkAnalyzer.discover2(subnet, defaultPort);

    await for (var data in stream.map((message) => message)) {
      if (data.exists) {
        yield PrinterDevice(name: "${data.ip}:$defaultPort", address: data.ip);
      }
    }
  }

  @override
  Future<PrinterConnectStatusResult> send(List<int> bytes, [TcpPrinterInput? model]) async {
    try {
      if (model != null) {
        // await _socket?.flush();
        // _socket?.destroy();
        // _socket = await Socket.connect(model.ipAddress, model.port, timeout: model.timeout);
      }

      _socket?.add(Uint8List.fromList(bytes));
      return PrinterConnectStatusResult(isSuccess: true);
    } catch (e, stackTrace) {
      return PrinterConnectStatusResult(
          isSuccess: false, exception: '${model?.ipAddress}:${model?.port}:${e}', stackTrace: stackTrace);
    }
  }

  @override
  Future<PrinterConnectStatusResult> connect(TcpPrinterInput model) async {
    try {
      _host = model.ipAddress;
      _port = model.port;
      await _socket?.flush();
      _socket?.destroy();
      _socket = await Socket.connect(model.ipAddress, model.port, timeout: model.timeout);
      return PrinterConnectStatusResult(isSuccess: true);
    } catch (e, stackTrace) {
      if (e is SocketException) {
        debugPrint('Err printer.connect SocketException: $e\n$stackTrace');
        await _socket?.flush();
        _socket?.close();
        _socket?.destroy();
      } else {
        debugPrint('Err printer.connect OtherException: $e\n$stackTrace');
        _socket?.destroy();
      }
      status = TCPStatus.none;
      return PrinterConnectStatusResult(
          isSuccess: false, exception: '${model.ipAddress}:${model.port}:${e}', stackTrace: stackTrace);
    }
  }

  /// [delayMs]: milliseconds to wait after destroying the socket
  @override
  Future<bool> disconnect({int? delayMs}) async {
    try {
      await _socket?.flush();
      _socket?.destroy();

      if (delayMs != null) {
        await Future.delayed(Duration(milliseconds: delayMs), () => null);
      }
      return true;
    } catch (e) {
      _socket?.destroy();
      status = TCPStatus.none;
      return false;
    }
  }

  /// Gets the current state of the TCP module
  Stream<TCPStatus> get currentStatus async* {
    yield* _statusStream.cast<TCPStatus>();
  }
}

import 'package:flutter/services.dart';

final flutterPrinterChannel = const MethodChannel('com.sersoluciones.flutter_pos_printer_platform');
final flutterPrinterEventChannelBT = const EventChannel('com.sersoluciones.flutter_pos_printer_platform/bt_state');
final flutterPrinterEventChannelUSB = const EventChannel('com.sersoluciones.flutter_pos_printer_platform/usb_state');
final iosChannel = const MethodChannel('flutter_pos_printer_platform/methods');
final iosStateChannel = const EventChannel('flutter_pos_printer_platform/state');

enum BTStatus { none, connecting, connected, scanning, stopScanning }

enum USBStatus { none, connecting, connected }

enum TCPStatus { none, connected }

class PrinterConnectStatusResult {
  final bool isSuccess;
  final Object? exception;
  final StackTrace? stackTrace;

  const PrinterConnectStatusResult({
    required this.isSuccess,
    this.exception,
    this.stackTrace,
  });
}

abstract class Printer {
  Future<bool> image(Uint8List image, {int threshold = 150});

  Future<bool> beep();

  Future<bool> pulseDrawer();

  Future<bool> setIp(String ipAddress);

  Future<bool> selfTest();
}

abstract class BasePrinterInput {}

//
abstract class PrinterConnector<T> {
  Future<PrinterConnectStatusResult> send(List<int> bytes, [T? model]);

  Future<PrinterConnectStatusResult> connect(T model);

  Future<bool> disconnect({int? delayMs});

  Future<PrinterConnectStatusResult> splitSend(List<List<int>> bytes, {
    T? model,
    int? fixedDelayMs,
    int? dynamicDelayBaseMs,
    double? sizeMultiplier,
    Duration? flushTimeout,
  });
}

abstract class GenericPrinter<T> extends Printer {
  PrinterConnector<T> connector;
  T model;

  GenericPrinter(this.connector, this.model) : super();

  List<int> encodeSetIP(String ip) {
    List<int> buffer = [0x1f, 0x1b, 0x1f, 0x91, 0x00, 0x49, 0x50];
    final List<String> splittedIp = ip.split('.');
    return buffer..addAll(splittedIp.map((e) => int.parse(e)).toList());
  }

  Future<bool> sendToConnector(List<int> Function() fn, {int? delayMs}) async {
    await connector.connect(model);
    final resp = await connector.send(fn());
    if (delayMs != null) {
      await Future.delayed(Duration(milliseconds: delayMs));
    }
    return resp.isSuccess;
  }
}

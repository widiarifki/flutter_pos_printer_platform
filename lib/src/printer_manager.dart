import 'dart:io';

import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';

enum PrinterType { bluetooth, usb, network }

class PrinterManager {
  final bluetoothPrinterConnector = BluetoothPrinterConnector.instance;
  final tcpPrinterConnector = TcpPrinterConnector.instance;
  final usbPrinterConnector = UsbPrinterConnector.instance;

  PrinterManager._();

  static PrinterManager _instance = PrinterManager._();

  static PrinterManager get instance => _instance;

  Stream<PrinterDevice> discovery({required PrinterType type, bool isBle = false, TcpPrinterInput? model}) {
    if (type == PrinterType.bluetooth && (Platform.isIOS || Platform.isAndroid)) {
      return bluetoothPrinterConnector.discovery(isBle: isBle);
    } else if (type == PrinterType.usb && (Platform.isAndroid || Platform.isWindows)) {
      return usbPrinterConnector.discovery();
    } else {
      return tcpPrinterConnector.discovery(model: model);
    }
  }

  Future<PrinterConnectStatusResult> connect({required PrinterType type, required BasePrinterInput model}) async {
    if (type == PrinterType.bluetooth && (Platform.isIOS || Platform.isAndroid)) {
      try {
        var conn = await bluetoothPrinterConnector.connect(model as BluetoothPrinterInput);
        return conn;
      } catch (e, stackTrace) {
        throw Exception('Err bluetoothPrinterConnector.connect: ${e}, $stackTrace');
      }
    } else if (type == PrinterType.usb && (Platform.isAndroid || Platform.isWindows)) {
      try {
        var conn = await usbPrinterConnector.connect(model as UsbPrinterInput);
        return conn;
      } catch (e, stackTrace) {
        throw Exception('Err usbPrinterConnector.connect: ${e}, $stackTrace');
      }
    } else {
      try {
        var conn = await tcpPrinterConnector.connect(model as TcpPrinterInput);
        return conn;
      } catch (e, stackTrace) {
        throw Exception('Err tcpPrinterConnector.connect: ${e}, $stackTrace');
      }
    }
  }

  Future<bool> disconnect({required PrinterType type, int? delayMs}) async {
    if (type == PrinterType.bluetooth && (Platform.isIOS || Platform.isAndroid)) {
      return await bluetoothPrinterConnector.disconnect();
    } else if (type == PrinterType.usb && (Platform.isAndroid || Platform.isWindows)) {
      return await usbPrinterConnector.disconnect(delayMs: delayMs);
    } else {
      return await tcpPrinterConnector.disconnect();
    }
  }

  Future<PrinterConnectStatusResult> send(
      {required PrinterType type, required List<int> bytes, BasePrinterInput? model}) async {
    if (type == PrinterType.bluetooth && (Platform.isIOS || Platform.isAndroid)) {
      return await bluetoothPrinterConnector.send(bytes);
    } else if (type == PrinterType.usb && (Platform.isAndroid || Platform.isWindows)) {
      return await usbPrinterConnector.send(bytes);
    } else {
      return await tcpPrinterConnector.send(bytes, model as TcpPrinterInput?);
    }
  }

  Future<PrinterConnectStatusResult> splitSend({
    required PrinterType type,
    required List<List<int>> bytes,
    BasePrinterInput? model,
    int? delayBetweenMs,
    int? dynamicDelayBaseMs,
    double? sizeMultiplier,
  }) async {
    if (type == PrinterType.bluetooth && (Platform.isIOS || Platform.isAndroid)) {
      return await bluetoothPrinterConnector.splitSend(bytes);
    } else if (type == PrinterType.usb && (Platform.isAndroid || Platform.isWindows)) {
      return await usbPrinterConnector.splitSend(bytes);
    } else {
      return await tcpPrinterConnector.splitSend(
        bytes,
        model: model as TcpPrinterInput?,
        fixedDelayMs: delayBetweenMs,
        dynamicDelayBaseMs: dynamicDelayBaseMs,
        sizeMultiplier: sizeMultiplier,
      );
    }
  }

  Stream<BTStatus> get stateBluetooth => bluetoothPrinterConnector.currentStatus.cast<BTStatus>();

  Stream<USBStatus> get stateUSB => usbPrinterConnector.currentStatus.cast<USBStatus>();

  Stream<TCPStatus> get stateTCP => tcpPrinterConnector.currentStatus.cast<TCPStatus>();

  BTStatus get currentStatusBT => bluetoothPrinterConnector.status;

  USBStatus get currentStatusUSB => usbPrinterConnector.status;

  TCPStatus get currentStatusTCP => tcpPrinterConnector.status;
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter_pos_printer_platform/discovery.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';

class UsbPrinterInput extends BasePrinterInput {
  final String? name;
  final String? vendorId;
  final String? productId;

  UsbPrinterInput({
    this.name,
    this.vendorId,
    this.productId,
  });
}

class UsbPrinterInfo {
  String vendorId;
  String productId;
  String manufacturer;
  String product;
  String name;
  String? model;
  bool isDefault = false;
  String deviceId;

  UsbPrinterInfo.Android({
    required this.vendorId,
    required this.productId,
    required this.manufacturer,
    required this.product,
    required this.name,
    required this.deviceId,
  });

  UsbPrinterInfo.Windows({
    required this.name,
    required this.model,
    required this.isDefault,
    this.vendorId = '',
    this.productId = '',
    this.manufacturer = '',
    this.product = '',
    this.deviceId = '',
  });
}

class UsbPrinterConnector implements PrinterConnector<UsbPrinterInput> {
  UsbPrinterConnector._()
      : vendorId = '',
        productId = '',
        name = '' {
    if (Platform.isAndroid)
      flutterPrinterEventChannelUSB.receiveBroadcastStream().listen((data) {
        if (data is int) {
          // log('Received event status usb: $data');
          _status = USBStatus.values[data];
          _statusStreamController.add(_status);
        }
      });
  }

  static UsbPrinterConnector _instance = UsbPrinterConnector._();

  static UsbPrinterConnector get instance => _instance;

  Stream<USBStatus> get _statusStream => _statusStreamController.stream;
  final StreamController<USBStatus> _statusStreamController = StreamController.broadcast();

  UsbPrinterConnector.Android({required this.vendorId, required this.productId}) : name = '';

  UsbPrinterConnector.Windows({required this.name})
      : vendorId = '',
        productId = '';

  String vendorId;
  String productId;
  String name;
  USBStatus _status = USBStatus.none;

  USBStatus get status => _status;

  setVendor(String vendorId) => this.vendorId = vendorId;

  setProduct(String productId) => this.productId = productId;

  setName(String name) => this.name = name;

  /// Gets the current state of the Bluetooth module
  Stream<USBStatus> get currentStatus async* {
    if (Platform.isAndroid) {
      yield* _statusStream.cast<USBStatus>();
    }
  }

  static DiscoverResult<UsbPrinterInfo> discoverPrinters() async {
    if (Platform.isAndroid) {
      final List<dynamic> results = await flutterPrinterChannel.invokeMethod('getList');
      return results
          .map((dynamic r) => PrinterDiscovered<UsbPrinterInfo>(
                name: r['product'],
                detail: UsbPrinterInfo.Android(
                  vendorId: r['vendorId'],
                  productId: r['productId'],
                  manufacturer: r['manufacturer'],
                  product: r['product'],
                  name: r['name'],
                  deviceId: r['deviceId'],
                ),
              ))
          .toList();
    }
    if (Platform.isWindows) {
      final List<dynamic> results = await flutterPrinterChannel.invokeMethod('getList');
      return results
          .map((dynamic result) => PrinterDiscovered<UsbPrinterInfo>(
                name: result['name'],
                detail:
                    UsbPrinterInfo.Windows(isDefault: result['default'], name: result['name'], model: result['model']),
              ))
          .toList();
    }
    return [];
  }

  Stream<PrinterDevice> discovery() async* {
    if (Platform.isAndroid) {
      final List<dynamic> results = await flutterPrinterChannel.invokeMethod('getList');
      for (final device in results) {
        var r = await device;
        yield PrinterDevice(
          name: r['product'],
          vendorId: r['vendorId'],
          productId: r['productId'],
          // name: r['name'],
        );
      }
    } else if (Platform.isWindows) {
      final List<dynamic> results = await flutterPrinterChannel.invokeMethod('getList');
      for (final device in results) {
        var r = await device;
        yield PrinterDevice(
          name: r['name'],
          // model: r['model'],
        );
      }
    }
  }

  Future<bool> _connect({UsbPrinterInput? model}) async {
    if (Platform.isAndroid) {
      Map<String, dynamic> params = {
        "vendor": int.parse(model?.vendorId ?? vendorId),
        "product": int.parse(model?.productId ?? productId)
      };
      return await flutterPrinterChannel.invokeMethod('connectPrinter', params);
    } else if (Platform.isWindows) {
      Map<String, dynamic> params = {"name": model?.name ?? name};
      return await flutterPrinterChannel.invokeMethod('connectPrinter', params) == 1 ? true : false;
    }
    return false;
  }

  Future<bool> _close() async {
    if (Platform.isWindows) return await flutterPrinterChannel.invokeMethod('close') == 1 ? true : false;
    return false;
  }

  @override
  Future<PrinterConnectStatusResult> connect(UsbPrinterInput model) async {
    try {
      return PrinterConnectStatusResult(isSuccess: await _connect(model: model));
    } catch (e, stackTrace) {
      return PrinterConnectStatusResult(isSuccess: false, exception: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<bool> disconnect({int? delayMs}) async {
    try {
      return await _close();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<PrinterConnectStatusResult> send(List<int> bytes, [UsbPrinterInput? model]) async {
    if (Platform.isAndroid)
      try {
        // final connected = await _connect();
        // if (!connected) return false;
        Map<String, dynamic> params = {"bytes": bytes};
        return PrinterConnectStatusResult(
          isSuccess: await flutterPrinterChannel.invokeMethod('printBytes', params) ?? false,
          exception: Exception('printBytes failed'),
        );
      } catch (e, stackTrace) {
        return PrinterConnectStatusResult(isSuccess: false, stackTrace: stackTrace, exception: e);
      }
    else if (Platform.isWindows)
      try {
        Map<String, dynamic> params = {"bytes": Uint8List.fromList(bytes)};
        return PrinterConnectStatusResult(
          isSuccess: await flutterPrinterChannel.invokeMethod('printBytes', params) == 1 ? true : false,
          exception: Exception('printBytes failed'),
        );
      } catch (e, stackTrace) {
        await this._close();
        return PrinterConnectStatusResult(isSuccess: false, exception: e, stackTrace: stackTrace);
      }
    else
      return PrinterConnectStatusResult(isSuccess: false, exception: Exception('else platform'));
  }

  @override
  Future<PrinterConnectStatusResult> splitSend(List<List<int>> bytes, {
    UsbPrinterInput? model,
    int? fixedDelayMs,
    int? dynamicDelayBaseMs,
    double? sizeMultiplier,
  }) async {
    final unsplitBytes = bytes.flattenedToList;
    if (Platform.isAndroid)
      try {
        // final connected = await _connect();
        // if (!connected) return false;
        Map<String, dynamic> params = {"bytes": unsplitBytes};
        return PrinterConnectStatusResult(
          isSuccess: await flutterPrinterChannel.invokeMethod('printBytes', params) ?? false,
          exception: Exception('printBytes failed'),
        );
      } catch (e, stackTrace) {
        return PrinterConnectStatusResult(isSuccess: false, stackTrace: stackTrace, exception: e);
      }
    else if (Platform.isWindows)
      try {
        Map<String, dynamic> params = {"bytes": Uint8List.fromList(unsplitBytes)};
        return PrinterConnectStatusResult(
          isSuccess: await flutterPrinterChannel.invokeMethod('printBytes', params) == 1 ? true : false,
          exception: Exception('printBytes failed'),
        );
      } catch (e, stackTrace) {
        await this._close();
        return PrinterConnectStatusResult(isSuccess: false, exception: e, stackTrace: stackTrace);
      }
    else
      return PrinterConnectStatusResult(isSuccess: false, exception: Exception('else platform'));
  }
}

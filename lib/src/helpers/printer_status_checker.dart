import 'dart:io';
import 'dart:typed_data';

class PrinterStatusChecker {
  static const List<List<int>> statusCommands = [
    [0x1B, 0x76], // ESC v - Epson
    [0x10, 0x04, 0x01], // DLE EOT n - Epson
    [0x10, 0x04, 0x02], // DLE EOT n - Epson (different status type)
    [0x10, 0x04, 0x03], // DLE EOT n - Epson (different status type)
    [0x10, 0x04, 0x04], // DLE EOT n - Epson (different status type)
    [0x1D, 0x72, 0x01], // GS r n - Generic/Star
    [0x1D, 0x72, 0x11], // GS r n - Generic/Star (different status type)
    [0x1B, 0x75, 0x0], // ESC u 0 - Star
    [0x1B, 0x69], // ESC i - Star
    [0x1B, 0x31], // ESC 1 - POS-X
    [0x1D, 0x49, 0x01], // GS I n - Generic status
    [0x1D, 0x49, 0x02], // GS I n - Generic status (different type)
    [0x1B, 0x74, 0x01], // ESC t n - Generic status
    [0x1B, 0x76, 0x01], // ESC v n - Rongta/Generic
    [0x1D, 0x61, 0x01], // GS a n - Generic status
    [0x1B, 0x40], // ESC @ - Initialize printer
  ];

  static final Map<String, List<int>> _workingCommands = {};

  static Future<bool> checkStatus(Socket socket, String printerKey,
      {int maxRetries = 3, Duration retryDelay = const Duration(milliseconds: 200)}) async {
    int retryCount = 0;

    while (retryCount < maxRetries) {
      // Try cached command first
      if (_workingCommands.containsKey(printerKey)) {
        try {
          final result = await _tryCommand(socket, _workingCommands[printerKey]!);
          if (result) return true;
        } catch (e) {
          print('Cached status command failed for $printerKey: $e');
        }
      }

      // Try each command
      for (var command in statusCommands) {
        try {
          final result = await _tryCommand(socket, command);
          if (result) {
            _workingCommands[printerKey] = command;
            return true;
          }
        } catch (e) {
          continue;
        }
      }

      retryCount++;
      if (retryCount < maxRetries) {
        await Future.delayed(retryDelay);
      }
    }

    return false;
  }

  static Future<bool> _tryCommand(Socket socket, List<int> command) async {
    try {
      socket.add(Uint8List.fromList(command));
      await socket.flush();
      await Future.delayed(Duration(milliseconds: 100));
      return true;
    } catch (e) {
      return false;
    }
  }
}

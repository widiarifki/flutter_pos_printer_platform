extension ReplaceNonAscii on String {
  String replaceNonAscii() {
    String cleaned = replaceAll("“", '"')
        .replaceAll("”", '"')
        .replaceAll("‘", "'")
        .replaceAll("’", "'")
        .replaceAll("‚", ",")
        .replaceAll("´", "'")
        .replaceAll("»", '"')
        .replaceAll(" ", ' ')
        .replaceAll("•", '.');
    return cleaned;
  }

  String replaceNonPrintable({String replaceWith = ' '}) {
    List<int> charCodes = <int>[];

    for (int codeUnit in codeUnits) {
      if (isPrintable(codeUnit)) {
        charCodes.add(codeUnit);
      } else {
        if (replaceWith.isNotEmpty) {
          charCodes.add(replaceWith.codeUnits[0]);
        }
      }
    }

    return String.fromCharCodes(charCodes);
  }
}

bool isPrintable(int codeUnit) {
  bool printable = true;

  if (codeUnit < 32) printable = false;
  if (codeUnit > 127) printable = false;

  return printable;
}

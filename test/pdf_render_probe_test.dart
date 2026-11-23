import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pi_qbank/pages/in_app_pdf_viewer_page.dart';

const pdfium =
    '/home/rashidsahriar/Pi-QBank/build/linux/x64/debug/pdfium/chromium%2F6555/lib/libpdfium.so';
const formula = '/home/rashidsahriar/Documents/Class 8/Formula Sheet.pdf';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full InAppPdfViewerPage renders formula sheet', (tester) async {
    Pdfrx.pdfiumModulePath = pdfium;
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: const InAppPdfViewerPage(
            filePath: formula,
            title: 'Formula Sheet',
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 150));
    }
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/opencode/app_formula_frame2.png')
        .writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
    // ignore: avoid_print
    print('SAVED app_formula_frame2');
  });
}

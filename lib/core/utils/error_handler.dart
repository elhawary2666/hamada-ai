// lib/core/utils/error_handler.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

void setupErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    _log.e('Flutter Error', error: details.exception, stackTrace: details.stack);
    if (kReleaseMode) {
      FlutterError.presentError(details);
    } else {
      FlutterError.dumpErrorToConsole(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.e('Platform Error', error: error, stackTrace: stack);
    return true;
  };
}

class ErrorBoundary extends StatefulWidget {
  const ErrorBoundary({super.key, required this.child});
  final Widget child;
  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorScreen(error: _error!);
    return widget.child;
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D1117),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 64, color: Color(0xFFF85149)),
        const SizedBox(height: 16),
        const Text('حصل خطأ غير متوقع',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: Color(0xFFCDD9E5), fontFamily: 'Cairo')),
        const SizedBox(height: 8),
        const Text('جرّب تقفل التطبيق وتفتحه تاني',
            style: TextStyle(fontSize: 14, color: Color(0xFF768390),
                fontFamily: 'Cairo')),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F8EF7)),
          icon:  const Icon(Icons.refresh, color: Colors.white),
          label: const Text('إعادة المحاولة',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          onPressed: () => Navigator.of(context, rootNavigator: true)
              .pushNamedAndRemoveUntil('/', (_) => false),
        ),
      ]),
    )),
  );
}

Future<T?> safeCall<T>(Future<T> Function() fn,
    {void Function(String)? onError}) async {
  try {
    return await fn();
  } catch (e, s) {
    _log.e('safeCall', error: e, stackTrace: s);
    onError?.call(_friendlyMessage(e));
    return null;
  }
}

String _friendlyMessage(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('network') || s.contains('socket'))
    return 'تأكد من الإنترنت وجرّب تاني 📶';
  if (s.contains('401') || s.contains('api key'))
    return 'الـ API Key غلط — روح الإعدادات 🔑';
  if (s.contains('429') || s.contains('rate limit'))
    return 'وصلت للحد المسموح — استنى دقيقة ⏳';
  return 'حصل خطأ — جرّب تاني بعد شوية';
}

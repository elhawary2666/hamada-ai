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
    // Override ErrorWidget builder so build errors get caught here
    ErrorWidget.builder = (FlutterErrorDetails details) {
      _log.e('Widget build error', error: details.exception);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _error = details.exception);
      });
      // Return a minimal fallback while we update state
      return const SizedBox.shrink();
    };
  }

  @override
  void dispose() {
    // Restore default ErrorWidget builder on dispose
    ErrorWidget.builder = (details) => ErrorWidget(details.exception);
    super.dispose();
  }

  void _reset() => setState(() => _error = null);

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorScreen(error: _error!, onRetry: _reset);
    return widget.child;
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

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
        if (!kReleaseMode) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              error.toString().substring(0, error.toString().length.clamp(0, 200)),
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF768390), fontFamily: 'monospace'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F8EF7)),
          icon:  const Icon(Icons.refresh, color: Colors.white),
          label: const Text('إعادة المحاولة',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          onPressed: onRetry,
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



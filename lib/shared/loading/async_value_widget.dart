import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../error/error_view.dart';
import 'loading_indicator.dart';

/// Renders a Riverpod [AsyncValue] as loading/error/data — the standard
/// shape every async read in this app should go through, instead of each
/// screen hand-rolling its own `when`.
class AsyncValueWidget<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final String Function(Object error)? errorMessage;
  final VoidCallback? onRetry;

  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.data,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const LoadingIndicator(),
      error: (error, stackTrace) => ErrorView(
        message:
            errorMessage?.call(error) ??
            'Something went wrong. Please try again.',
        onRetry: onRetry,
      ),
    );
  }
}

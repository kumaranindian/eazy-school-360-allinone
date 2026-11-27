import 'package:flutter/material.dart';

/// The app's [Form]. On a submit that fails validation it:
///
/// * keeps re-validating as the user types, so an error clears as soon as
///   the field is fixed (SET-01-OBS-02);
/// * scrolls to the first field in error and focuses it (STF-01-OBS-01).
///
/// Callers keep calling `formKey.currentState!.validate()`; the key holds
/// this form's [FormState]. Use [FormScrollView] (not a lazy `ListView`) for
/// a long form's body, so every field is built and validated.
class AppForm extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final Widget child;
  final VoidCallback? onChanged;

  const AppForm({
    super.key,
    required this.formKey,
    required this.child,
    this.onChanged,
  });

  @override
  State<AppForm> createState() => _AppFormState();
}

class _AppFormState extends State<AppForm> {
  var _mode = AutovalidateMode.disabled;

  void _failed() {
    if (_mode != AutovalidateMode.onUserInteraction) {
      setState(() => _mode = AutovalidateMode.onUserInteraction);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final formContext = widget.formKey.currentContext;
      if (formContext != null && formContext.mounted) {
        revealFirstFormError(formContext);
      }
    });
  }

  @override
  Widget build(BuildContext context) => _RevealingForm(
    key: widget.formKey,
    autovalidateMode: _mode,
    onChanged: widget.onChanged,
    onFailed: _failed,
    child: widget.child,
  );
}

class _RevealingForm extends Form {
  final VoidCallback onFailed;

  const _RevealingForm({
    super.key,
    required super.child,
    super.autovalidateMode,
    super.onChanged,
    required this.onFailed,
  });

  @override
  FormState createState() => _RevealingFormState();
}

class _RevealingFormState extends FormState {
  @override
  bool validate() {
    final ok = super.validate();
    if (!ok) (widget as _RevealingForm).onFailed();
    return ok;
  }
}

/// Scrolls to the first [FormField] under [formContext] that shows an error
/// and focuses it. Returns whether one was found.
bool revealFirstFormError(BuildContext formContext) {
  Element? first;
  void find(Element e) {
    if (first != null) return;
    if (e is StatefulElement && e.state is FormFieldState) {
      if ((e.state as FormFieldState).hasError) {
        first = e;
        return;
      }
    }
    e.visitChildren(find);
  }

  formContext.visitChildElements(find);
  final target = first;
  if (target == null) return false;
  Scrollable.ensureVisible(
    target,
    alignment: 0.2,
    duration: const Duration(milliseconds: 200),
  );
  FocusNode? node;
  void focus(Element e) {
    if (node != null) return;
    final w = e.widget;
    if (w is EditableText) {
      node = w.focusNode;
      return;
    }
    if (w is Focus && w.focusNode != null) {
      node = w.focusNode;
      return;
    }
    e.visitChildren(focus);
  }

  target.visitChildren(focus);
  node?.requestFocus();
  return true;
}

/// A long form's scrolling body. Unlike `ListView` it builds every child,
/// so fields scrolled out of view are still validated (STF-01-DEF-01).
class FormScrollView extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;

  const FormScrollView({
    super.key,
    required this.children,
    this.padding,
    this.controller,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// A `buildCounter` that counts what will be saved: the text without the
/// blank lines and spaces around it, so an empty-looking box never shows
/// "6/4000" (COM-01-OBS-01).
InputCounterWidgetBuilder trimmedCounter(TextEditingController controller) =>
    (context, {required currentLength, required isFocused, maxLength}) => Text(
      '${controller.text.trim().length}/${maxLength ?? ''}',
      style: Theme.of(context).textTheme.bodySmall,
      semanticsLabel: '${controller.text.trim().length} characters',
    );

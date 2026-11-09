import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/branding/tenant_branding.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/color_math.dart';

/// Edits the seven brand colours: a swatch (tap for sliders) and a hex field
/// per colour, with the readability problem, if any, shown under it. Colours
/// that would be unreadable are flagged here and refused by the server.
class BrandColorEditor extends StatelessWidget {
  final BrandColors colors;
  final ValueChanged<BrandColors> onChanged;
  final bool enabled;

  const BrandColorEditor({
    super.key,
    required this.colors,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final problems = colors.problems();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in BrandToken.values)
          _ColorRow(
            key: ValueKey('color-${t.name}'),
            token: t,
            color: colors.of(t),
            problem: problems[t],
            enabled: enabled,
            onChanged: (c) => onChanged(colors.with_(t, c)),
          ),
      ],
    );
  }
}

class _ColorRow extends StatefulWidget {
  final BrandToken token;
  final Color color;
  final String? problem;
  final bool enabled;
  final ValueChanged<Color> onChanged;

  const _ColorRow({
    super.key,
    required this.token,
    required this.color,
    required this.problem,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  late final TextEditingController _hex = TextEditingController(
    text: ColorMath.hex(widget.color),
  );
  final FocusNode _focus = FocusNode();
  bool _invalid = false;

  @override
  void didUpdateWidget(_ColorRow old) {
    super.didUpdateWidget(old);
    // Follow outside changes (preset picked, slider moved) unless the user is
    // mid-typing something that is not a colour yet.
    final shown = ColorMath.parse(_hex.text);
    if (widget.color != old.color && shown != widget.color) {
      _hex.text = ColorMath.hex(widget.color);
      _invalid = false;
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String v) {
    // Only a person typing in the field is an edit. A phone keyboard can echo
    // the field's text back when the app rewrites it (a preset was picked);
    // taking that as typing would put the previous colour back.
    if (!_focus.hasFocus) return;
    final c = ColorMath.parse(v.startsWith('#') ? v : '#$v');
    setState(() => _invalid = c == null);
    if (c != null) widget.onChanged(c);
  }

  Future<void> _pick() async {
    final c = await showDialog<Color>(
      context: context,
      builder: (_) => _SliderDialog(initial: widget.color, token: widget.token),
    );
    if (c != null) widget.onChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final problem = _invalid ? 'Use a colour like #16856A' : widget.problem;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Choose ${widget.token.label} colour',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.enabled ? _pick : null,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(widget.token.label, style: text.titleSmall)),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _hex,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  maxLength: 7,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    labelText: 'Hex',
                    errorText: _invalid ? '' : null,
                  ),
                  onChanged: _typed,
                ),
              ),
            ],
          ),
          if (problem != null && problem.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 56),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  problem,
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SliderDialog extends StatefulWidget {
  final Color initial;
  final BrandToken token;
  const _SliderDialog({required this.initial, required this.token});

  @override
  State<_SliderDialog> createState() => _SliderDialogState();
}

class _SliderDialogState extends State<_SliderDialog> {
  late HSLColor _hsl = HSLColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final c = _hsl.toColor();
    Widget slider(String label, double v, double max, ValueChanged<double> f) =>
        Row(
          children: [
            SizedBox(width: 92, child: Text(label)),
            Expanded(
              child: Slider(value: v.clamp(0, max), max: max, onChanged: f),
            ),
          ],
        );
    return AlertDialog(
      title: Text(widget.token.label),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                ColorMath.hex(c),
                style: TextStyle(color: ColorMath.onColor(c)),
              ),
            ),
            slider(
              'Hue',
              _hsl.hue,
              360,
              (v) => setState(() => _hsl = _hsl.withHue(v)),
            ),
            slider(
              'Saturation',
              _hsl.saturation,
              1,
              (v) => setState(() => _hsl = _hsl.withSaturation(v)),
            ),
            slider(
              'Lightness',
              _hsl.lightness,
              1,
              (v) => setState(() => _hsl = _hsl.withLightness(v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(c),
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}

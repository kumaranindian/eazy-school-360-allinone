import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/regional/country.dart';
import '../../core/regional/currency.dart';
import '../../core/regional/regional_settings.dart';
import '../../core/regional/time_zones.dart';
import '../../core/theme/app_spacing.dart';

/// Country, currency, time zone and date format pickers, used when a school is
/// created and in Settings -> Regional. Choosing a country pre-fills the other
/// three (each can still be changed afterwards).
class RegionalSettingsEditor extends StatelessWidget {
  final RegionalSettings value;
  final ValueChanged<RegionalSettings> onChanged;
  final bool enabled;

  /// The currency can no longer be changed (money exists).
  final bool currencyLocked;

  const RegionalSettingsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.currencyLocked = false,
  });

  static List<String> allZones() {
    TimeZones.ensureInitialized();
    final names = tz.timeZoneDatabase.locations.keys.toList()..sort();
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final country = Countries.byCode(value.countryCode);
    final zones = <String>{...?country?.timezones, value.timezone}.toList();
    final currencyKnown = Currencies.isSupported(value.currency);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('country-${value.countryCode}'),
          value: Countries.byCode(value.countryCode)?.code,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Country',
            prefixIcon: Icon(Icons.public_outlined),
          ),
          items: [
            for (final c in Countries.all)
              DropdownMenuItem(value: c.code, child: Text(c.name)),
          ],
          onChanged: enabled
              ? (code) {
                  final c = Countries.byCode(code);
                  if (c == null) return;
                  final next = RegionalSettings.forCountry(c);
                  // Money already exists: keep the school's currency.
                  onChanged(
                    currencyLocked
                        ? next.copyWith(currency: value.currency)
                        : next,
                  );
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: ValueKey('currency-${value.currency}-$currencyLocked'),
          value: currencyKnown ? value.currency : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Currency',
            prefixIcon: const Icon(Icons.payments_outlined),
            helperText: currencyLocked
                ? 'Locked: fees or payments already exist in this currency.'
                : 'Cannot be changed once the first fee or payment is created.',
            helperMaxLines: 2,
          ),
          items: [
            for (final c in Currencies.all)
              DropdownMenuItem(
                value: c.code,
                child: Text('${c.code} - ${c.name}'),
              ),
          ],
          onChanged: enabled && !currencyLocked
              ? (code) {
                  if (code != null) onChanged(value.copyWith(currency: code));
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownMenu<String>(
          key: ValueKey('tz-${value.timezone}-${value.countryCode}'),
          initialSelection: value.timezone,
          enabled: enabled,
          expandedInsets: EdgeInsets.zero,
          enableFilter: true,
          requestFocusOnTap: true,
          leadingIcon: const Icon(Icons.schedule_outlined),
          label: const Text('Time zone'),
          helperText:
              'The school\'s days, deadlines and reminders follow this zone.',
          dropdownMenuEntries: [
            // This country's zones first, then everything else.
            for (final z in zones)
              DropdownMenuEntry(
                value: z,
                label: '$z  (${TimeZones.offsetLabel(z)})',
              ),
            for (final z in allZones())
              if (!zones.contains(z)) DropdownMenuEntry(value: z, label: z),
          ],
          onSelected: (z) {
            if (z != null) onChanged(value.copyWith(timezone: z));
          },
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: ValueKey('df-${value.dateFormat}'),
          value: DateFormats.all.contains(value.dateFormat)
              ? value.dateFormat
              : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Date format',
            prefixIcon: Icon(Icons.calendar_today_outlined),
          ),
          items: [
            for (final f in DateFormats.all)
              DropdownMenuItem(value: f, child: Text(f)),
          ],
          onChanged: enabled
              ? (f) {
                  if (f != null) onChanged(value.copyWith(dateFormat: f));
                }
              : null,
        ),
      ],
    );
  }
}

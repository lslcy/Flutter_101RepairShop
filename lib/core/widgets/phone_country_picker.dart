import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';
import '../validation/phone_country_number.dart';

/// A searchable country selector with the same typography and icons as the form.
class PhoneCountryPicker extends StatelessWidget {
  const PhoneCountryPicker({
    super.key,
    required this.countryCode,
    required this.onChanged,
    this.enabled = true,
  });

  final String countryCode;
  final ValueChanged<String> onChanged;
  final bool enabled;

  static final _service = CountryService();

  @override
  Widget build(BuildContext context) {
    final country = _service.findByCode(countryCode);
    final callingCode = PhoneCountryNumber.callingCodeFor(countryCode)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Country code',
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Country code',
          child: OutlinedButton(
            key: const ValueKey('phone-country-selector'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: enabled
                ? () async {
                    FocusScope.of(context).unfocus();
                    final selected = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (context) => Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.viewInsetsOf(context).bottom,
                        ),
                        child: FractionallySizedBox(
                          heightFactor: 0.85,
                          child: _CountryList(selected: countryCode),
                        ),
                      ),
                    );
                    if (context.mounted && selected != null) {
                      onChanged(selected);
                    }
                  }
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${country?.name ?? countryCode} ($callingCode)',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more_outlined),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CountryList extends StatefulWidget {
  const _CountryList({required this.selected});

  final String selected;

  @override
  State<_CountryList> createState() => _CountryListState();
}

class _CountryListState extends State<_CountryList> {
  static final _countries =
      CountryService()
          .getAll()
          .where(
            (country) =>
                PhoneCountryNumber.supportsCountry(country.countryCode),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = _query.trim().toLowerCase();
    final codeQuery = query.replaceFirst(RegExp(r'^\+'), '');
    final countries = _countries.where((country) {
      return query.isEmpty ||
          country.name.toLowerCase().contains(query) ||
          country.countryCode.toLowerCase() == query ||
          PhoneCountryNumber.callingCodeFor(country.countryCode)!
              .substring(1)
              .startsWith(codeQuery);
    }).toList();
    if (query.isEmpty) {
      final selectedIndex = countries.indexWhere(
        (country) => country.countryCode == widget.selected,
      );
      if (selectedIndex >= 0) {
        countries.insert(0, countries.removeAt(selectedIndex));
      }
    }
    return SafeArea(
      top: false,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: const Text(
                            'Choose country',
                            style: AppTextStyles.heading3,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close country selector',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_outlined),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    key: const ValueKey('phone-country-search'),
                    textInputAction: TextInputAction.search,
                    onChanged: (value) => setState(() => _query = value),
                    style: AppTextStyles.body,
                    decoration: const InputDecoration(
                      labelText: 'Search country or code',
                      prefixIcon: Icon(Icons.search_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          if (countries.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No countries found. Try a name or dialing code.',
                  style: AppTextStyles.body.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: countries.length,
              itemBuilder: (context, index) {
                final country = countries[index];
                final selected = country.countryCode == widget.selected;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  minTileHeight: 64,
                  selected: selected,
                  title: Text(country.name, style: AppTextStyles.bodyMedium),
                  subtitle: Text(
                    PhoneCountryNumber.callingCodeFor(country.countryCode)!,
                    style: AppTextStyles.bodySmall,
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle_outline)
                      : null,
                  onTap: () => Navigator.of(context).pop(country.countryCode),
                );
              },
            ),
        ],
      ),
    );
  }
}

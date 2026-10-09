import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/address_parts.dart';
import '../services/address_location_service.dart';
import '../theme/app_spacing.dart';
import 'app_text_field.dart';

export '../models/address_parts.dart';

/// Editable address fields with a single, user-initiated location lookup.
class AddressInput extends ConsumerStatefulWidget {
  const AddressInput({
    super.key,
    required this.controller,
    this.enabled = true,
    this.focusNode,
    this.labelStyle,
  });

  /// Stores the readable address expected by the existing customer repository.
  final TextEditingController controller;
  final bool enabled;
  final FocusNode? focusNode;
  final TextStyle? labelStyle;

  @override
  ConsumerState<AddressInput> createState() => _AddressInputState();
}

class _AddressInputState extends ConsumerState<AddressInput> {
  final _houseController = TextEditingController();
  final _streetController = TextEditingController();
  final _barangayController = TextEditingController();
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _houseFocus = FocusNode();
  final _streetFocus = FocusNode();
  final _barangayFocus = FocusNode();
  final _cityFocus = FocusNode();
  final _provinceFocus = FocusNode();
  final _postalFocus = FocusNode();

  AddressParts _metadata = const AddressParts();
  bool _updatingFields = false;
  bool _writingMain = false;
  bool _legacyUnedited = false;
  bool _houseEdited = false;
  List<String> _lastFieldTexts = const [];
  String _lastMainText = '';
  bool _locating = false;
  bool _messageIsError = false;
  String? _message;
  LocationRecoveryAction _recoveryAction = LocationRecoveryAction.none;
  int _request = 0;

  List<TextEditingController> get _subControllers => [
    _houseController,
    _streetController,
    _barangayController,
    _cityController,
    _provinceController,
    _postalCodeController,
  ];

  @override
  void initState() {
    super.initState();
    _hydrate();
    for (final controller in _subControllers) {
      controller.addListener(_fieldsChanged);
    }
    widget.controller.addListener(_mainChanged);
  }

  @override
  void didUpdateWidget(covariant AddressInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_mainChanged);
      widget.controller.addListener(_mainChanged);
      _request++;
      _locating = false;
      _message = null;
      _recoveryAction = LocationRecoveryAction.none;
      _hydrateAfterBuild();
    }
    if (!widget.enabled && oldWidget.enabled) {
      _request++;
      _locating = false;
    }
  }

  void _hydrate() {
    _lastMainText = widget.controller.text;
    _metadata = AddressParts.fromString(widget.controller.text);
    _legacyUnedited = widget.controller.text.trim().isNotEmpty;
    _houseEdited = _metadata.houseUnit?.trim().isNotEmpty ?? false;
    _updatingFields = true;
    try {
      _houseController.text = _metadata.houseUnit ?? '';
      _streetController.text = _metadata.street ?? '';
      _barangayController.text = _metadata.barangay ?? '';
      _cityController.text = _metadata.city ?? '';
      _provinceController.text = _metadata.province ?? '';
      _postalCodeController.text = _metadata.postalCode ?? '';
      _captureFieldTexts();
    } finally {
      _updatingFields = false;
    }
  }

  void _hydrateAfterBuild() {
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controller != controller) return;
      _hydrate();
      setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _mainChanged() {
    if (_writingMain || widget.controller.text == _lastMainText) return;
    _request++;
    _locating = false;
    _message = null;
    _recoveryAction = LocationRecoveryAction.none;
    _hydrateAfterBuild();
  }

  void _captureFieldTexts() {
    _lastFieldTexts = _subControllers
        .map((controller) => controller.text)
        .toList();
  }

  void _fieldsChanged() {
    if (_updatingFields) return;
    final texts = _subControllers.map((controller) => controller.text).toList();
    if (texts.asMap().entries.every(
      (entry) => entry.value == _lastFieldTexts[entry.key],
    )) {
      return;
    }
    if (texts.first != _lastFieldTexts.first) _houseEdited = true;
    _lastFieldTexts = texts;
    _legacyUnedited = false;
    _request++;
    _locating = false;
    _message = null;
    _recoveryAction = LocationRecoveryAction.none;
    _syncMain();
    if (mounted) setState(() {});
  }

  AddressParts get _currentParts => AddressParts(
    houseUnit: _houseController.text,
    street: _streetController.text,
    barangay: _barangayController.text,
    city: _cityController.text,
    province: _provinceController.text,
    postalCode: _postalCodeController.text,
    country: _metadata.country,
    additionalDetails: _metadata.additionalDetails,
  );

  void _syncMain() {
    final combined = _currentParts.combine();
    if (widget.controller.text == combined) return;
    _lastMainText = combined;
    _writingMain = true;
    try {
      widget.controller.value = TextEditingValue(
        text: combined,
        selection: TextSelection.collapsed(offset: combined.length),
      );
    } finally {
      _writingMain = false;
    }
  }

  bool get _hasLocalDetail =>
      _streetController.text.trim().isNotEmpty ||
      _barangayController.text.trim().isNotEmpty;

  bool get _isComplete =>
      _hasLocalDetail &&
      _cityController.text.trim().isNotEmpty &&
      _provinceController.text.trim().isNotEmpty;

  void _fillIfAvailable(TextEditingController controller, String? value) {
    if (value != null && value.trim().isNotEmpty) {
      controller.text = value.trim();
    }
  }

  Future<void> _useLocation() async {
    if (_locating || !widget.enabled) return;
    FocusScope.of(context).unfocus();
    final request = ++_request;
    setState(() {
      _locating = true;
      _message = null;
      _recoveryAction = LocationRecoveryAction.none;
    });
    try {
      final parts = await ref
          .read(addressLocationServiceProvider)
          .getCurrentAddressParts();
      if (!mounted || request != _request || !widget.enabled) return;
      _updatingFields = true;
      try {
        if (!_houseEdited) _fillIfAvailable(_houseController, parts.houseUnit);
        _fillIfAvailable(_streetController, parts.street);
        _fillIfAvailable(_barangayController, parts.barangay);
        _fillIfAvailable(_cityController, parts.city);
        _fillIfAvailable(_provinceController, parts.province);
        _fillIfAvailable(_postalCodeController, parts.postalCode);
        _metadata = parts;
        _legacyUnedited = false;
        _captureFieldTexts();
      } finally {
        _updatingFields = false;
      }
      _syncMain();
      setState(() {
        _messageIsError = false;
        _message = _isComplete
            ? 'Address filled in. Review the details and add your house or unit number if needed.'
            : 'Location found. Fill in the missing address details below.';
      });
    } on AddressLocationException catch (error) {
      if (!mounted || request != _request || !widget.enabled) return;
      setState(() {
        _messageIsError = true;
        _message = error.message;
        _recoveryAction = error.recoveryAction;
      });
    } catch (_) {
      if (!mounted || request != _request || !widget.enabled) return;
      setState(() {
        _messageIsError = true;
        _message =
            'We could not find your address. Try again or enter it manually.';
      });
    } finally {
      if (mounted && request == _request) {
        setState(() => _locating = false);
      }
    }
  }

  void _enterManually() {
    _request++;
    setState(() => _locating = false);
    _streetFocus.requestFocus();
  }

  Future<void> _openSettings() async {
    try {
      final service = ref.read(addressLocationServiceProvider);
      final opened = _recoveryAction == LocationRecoveryAction.appSettings
          ? await service.openAppSettings()
          : await service.openLocationSettings();
      if (!mounted) return;
      setState(() {
        _message = opened
            ? 'After enabling location, tap Use my location again.'
            : 'Open your phone settings to allow location, or enter your address manually.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Open your phone settings to allow location, or enter your address manually.';
      });
    }
  }

  @override
  void dispose() {
    _request++;
    widget.controller.removeListener(_mainChanged);
    for (final controller in _subControllers) {
      controller.removeListener(_fieldsChanged);
      controller.dispose();
    }
    for (final focus in [
      _houseFocus,
      _streetFocus,
      _barangayFocus,
      _cityFocus,
      _provinceFocus,
      _postalFocus,
    ]) {
      focus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Enter a street or barangay, plus your city and province.'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: widget.enabled && !_locating ? _useLocation : null,
              icon: _locating
                  ? MediaQuery.disableAnimationsOf(context)
                        ? const Icon(Icons.hourglass_empty_outlined, size: 20)
                        : const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                  : const Icon(Icons.my_location_outlined, size: 20),
              label: Text(
                _locating ? 'Finding your address...' : 'Use my location',
              ),
            ),
            if (_locating)
              TextButton(
                onPressed: _enterManually,
                child: const Text('Enter manually'),
              ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              _message!,
              style: TextStyle(
                color: _messageIsError ? colors.error : colors.onSurfaceVariant,
              ),
            ),
          ),
          if (_recoveryAction != LocationRecoveryAction.none)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.enabled ? _openSettings : null,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Open settings'),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'House / unit no. (optional)',
          labelStyle: widget.labelStyle,
          hint: 'e.g. Unit 5, Block 3',
          controller: _houseController,
          focusNode: widget.focusNode ?? _houseFocus,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _streetFocus.requestFocus(),
          autofillHints: const [AutofillHints.streetAddressLevel4],
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Street / subdivision',
          labelStyle: widget.labelStyle,
          hint: 'e.g. Rizal Avenue',
          controller: _streetController,
          focusNode: _streetFocus,
          enabled: widget.enabled,
          keyboardType: TextInputType.streetAddress,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _barangayFocus.requestFocus(),
          autofillHints: const [AutofillHints.streetAddressLine1],
          validator: (_) => !_legacyUnedited && !_hasLocalDetail
              ? 'Enter a street or barangay.'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Barangay',
          labelStyle: widget.labelStyle,
          hint: 'e.g. Mankilam',
          controller: _barangayController,
          focusNode: _barangayFocus,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _cityFocus.requestFocus(),
          autofillHints: const [AutofillHints.streetAddressLevel3],
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'City / municipality (required)',
          labelStyle: widget.labelStyle,
          hint: 'e.g. Tagum City',
          controller: _cityController,
          focusNode: _cityFocus,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _provinceFocus.requestFocus(),
          autofillHints: const [AutofillHints.addressCity],
          validator: (value) =>
              !_legacyUnedited && (value?.trim().isEmpty ?? true)
              ? 'Enter your city or municipality.'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Province (required)',
          labelStyle: widget.labelStyle,
          hint: 'e.g. Davao del Norte',
          controller: _provinceController,
          focusNode: _provinceFocus,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _postalFocus.requestFocus(),
          autofillHints: const [AutofillHints.addressState],
          validator: (value) =>
              !_legacyUnedited && (value?.trim().isEmpty ?? true)
              ? 'Enter your province.'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Postal code (optional)',
          labelStyle: widget.labelStyle,
          hint: 'e.g. 8100',
          controller: _postalCodeController,
          focusNode: _postalFocus,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.postalCode],
        ),
      ],
    );
  }
}

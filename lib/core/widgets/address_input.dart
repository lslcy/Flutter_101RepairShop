import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/address_location_service.dart';
import 'app_text_field.dart';

/// A required address with manual input and an optional, user-initiated lookup.
class AddressInput extends ConsumerStatefulWidget {
  const AddressInput({
    super.key,
    required this.controller,
    this.enabled = true,
    this.focusNode,
    this.labelStyle,
    this.maxLines = 4,
  });

  final TextEditingController controller;
  final bool enabled;
  final FocusNode? focusNode;
  final TextStyle? labelStyle;
  final int maxLines;

  @override
  ConsumerState<AddressInput> createState() => _AddressInputState();
}

class _AddressInputState extends ConsumerState<AddressInput> {
  bool _locating = false;
  String? _suggestion;
  String? _message;
  LocationRecoveryAction _recoveryAction = LocationRecoveryAction.none;
  int _request = 0;

  Future<void> _useLocation() async {
    if (_locating || !widget.enabled) return;
    FocusScope.of(context).unfocus();
    final request = ++_request;
    setState(() {
      _locating = true;
      _suggestion = null;
      _message = null;
      _recoveryAction = LocationRecoveryAction.none;
    });
    try {
      final address = await ref
          .read(addressLocationServiceProvider)
          .getCurrentAddress();
      if (!mounted || request != _request) return;
      setState(() {
        if (address.trim().isEmpty) {
          _message = 'No address was found. Please type your address below.';
        } else {
          _suggestion = address.trim();
        }
      });
    } on AddressLocationException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _message = error.message;
        _recoveryAction = error.recoveryAction;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(
        () => _message =
            'We could not find your address. Try again or enter it manually.',
      );
    } finally {
      if (mounted && request == _request) setState(() => _locating = false);
    }
  }

  void _cancelLookup() {
    _request++;
    setState(() => _locating = false);
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
            ? 'After enabling location, tap Use my location again, or type your address below.'
            : 'Open your phone settings to allow location, or type your address below.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Open your phone settings to allow location, or type your address below.',
        );
      }
    }
  }

  void _applySuggestion() {
    if (!widget.enabled || _suggestion == null) return;
    final address = _suggestion!;
    widget.controller.value = TextEditingValue(
      text: address,
      selection: TextSelection.collapsed(offset: address.length),
    );
    setState(() {
      _suggestion = null;
      _message = 'Address filled in. Review it and add your house or unit number if needed.';
      _recoveryAction = LocationRecoveryAction.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Use your phone location or enter your complete address below.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
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
                onPressed: _cancelLookup,
                child: const Text('Enter manually'),
              ),
          ],
        ),
        if (_suggestion != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Address found',
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _suggestion!,
                  style: TextStyle(color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 6),
                Text(
                  'Check that this is the address you want to save.',
                  style: TextStyle(color: colors.onPrimaryContainer),
                ),
                TextButton(
                  onPressed: widget.enabled ? _applySuggestion : null,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onPrimaryContainer,
                  ),
                  child: const Text('Use this address'),
                ),
              ],
            ),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _message!,
              style: TextStyle(color: colors.onSurfaceVariant),
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
        const SizedBox(height: 12),
        AppTextField(
          label: 'Address (required)',
          labelStyle: widget.labelStyle,
          hint: 'House / unit, street, barangay, city, province',
          helperText:
              'Include your postal code and a nearby landmark if helpful.',
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          keyboardType: TextInputType.streetAddress,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.fullStreetAddress],
          maxLines: widget.maxLines,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter your address or use your current location.'
              : null,
        ),
      ],
    );
  }
}

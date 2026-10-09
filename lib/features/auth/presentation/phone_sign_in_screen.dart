import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/account_errors.dart';
import '../../../core/validation/phone_country_number.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/phone_country_picker.dart';
import '../data/auth_repository.dart';

// Keep SMS rate-limit feedback when users leave and return to this screen.
final _phoneCodeCooldownProvider =
    StateNotifierProvider<_PhoneCodeCooldown, int>(
      (ref) => _PhoneCodeCooldown(),
    );

class _PhoneCodeCooldown extends StateNotifier<int> {
  _PhoneCodeCooldown() : super(0);

  Timer? _timer;

  void start() {
    _timer?.cancel();
    state = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      state = (60 - timer.tick).clamp(0, 60);
      if (state == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class PhoneSignInScreen extends ConsumerStatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  ConsumerState<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends ConsumerState<PhoneSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _feedbackKey = GlobalKey();
  int get _secondsRemaining => ref.read(_phoneCodeCooldownProvider);
  String? _phoneForCode;
  String _countryCode = 'PH';
  bool _syncingCountry = false;
  String? _errorMessage;
  bool _sending = false;
  bool _verifying = false;

  bool get _isBusy => _sending || _verifying;
  bool get _hasCode => _phoneForCode != null;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_syncCountryFromPhone);
  }

  ResolvedPhoneNumber? _resolvePhone() => PhoneCountryNumber.resolve(
    _phoneController.text,
    countryCode: _countryCode,
  );

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your phone number';
    if (PhoneCountryNumber.resolve(value, countryCode: _countryCode) == null) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  void _syncCountryFromPhone() {
    if (_syncingCountry || _hasCode || _isBusy) return;
    final input = _phoneController.text.trim();
    final compact = input.replaceAll(RegExp(r'[\s().-]'), '');
    final international = input.startsWith('+') || input.startsWith('00');
    final philippinePrefix =
        _countryCode == 'PH' && RegExp(r'^639\d{9}$').hasMatch(compact);
    if (!international && !philippinePrefix) return;
    final resolved = _resolvePhone();
    if (resolved == null) return;
    _syncingCountry = true;
    try {
      setState(() {
        _countryCode = resolved.countryCode;
        _errorMessage = null;
      });
      _phoneController.value = TextEditingValue(
        text: resolved.nationalNumber,
        selection: TextSelection.collapsed(
          offset: resolved.nationalNumber.length,
        ),
      );
    } finally {
      _syncingCountry = false;
    }
  }

  void _selectCountry(String countryCode) {
    if (_isBusy) return;
    setState(() {
      _countryCode = countryCode;
      _errorMessage = null;
    });
    _phoneFocus.requestFocus();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _reveal(BuildContext fieldContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !fieldContext.mounted) return;
      Scrollable.ensureVisible(
        fieldContext,
        alignment: 0.2,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
      );
    });
  }

  bool _validate() {
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isEmpty) return true;
    (_hasCode ? _codeFocus : _phoneFocus).requestFocus();
    _reveal(invalid.first.context);
    return false;
  }

  void _startCooldown() {
    ref.read(_phoneCodeCooldownProvider.notifier).start();
  }

  void _clearError(String _) {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  void _showError(Object error, {required bool verifying}) {
    final message = error.toString().toLowerCase();
    final code = error is AuthException ? error.code : null;
    final limited =
        code == 'over_sms_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        message.contains('rate limit') ||
        message.contains('too many requests');
    final unavailable =
        code == 'phone_provider_disabled' ||
        code == 'sms_send_failed' ||
        code == 'sms_provider_disabled' ||
        message.contains('sms provider') ||
        message.contains('phone provider is disabled') ||
        message.contains('phone logins are disabled') ||
        message.contains('unsupported phone provider');
    final expired =
        code == 'otp_expired' ||
        message.contains('expired') ||
        message.contains('invalid token') ||
        message.contains('invalid otp');
    final connection =
        message.contains('socket') ||
        message.contains('network') ||
        message.contains('timeout');
    setState(() {
      _errorMessage = limited
          ? 'Too many requests. Wait a minute before requesting another code.'
          : unavailable
          ? 'Phone sign-in is unavailable right now. Use email or Google, or try again later.'
          : verifying && expired
          ? 'That code is incorrect or has expired. Check the latest SMS or request a new code.'
          : connection
          ? 'We could not connect. Check your internet connection and try again.'
          : friendlyAccountError(
              error,
              fallback: verifying
                  ? 'We could not verify that code. Check the latest SMS and try again.'
                  : 'We could not send a code. Check your phone number and try again.',
            );
    });
    if (limited) _startCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final feedbackContext = _feedbackKey.currentContext;
      if (mounted && feedbackContext != null) _reveal(feedbackContext);
    });
  }

  Future<void> _sendCode() async {
    if (_isBusy || _secondsRemaining > 0) return;
    if (!_hasCode && !_validate()) return;
    final phone = _phoneForCode ?? _resolvePhone()!.e164;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authStateProvider.notifier).sendPhoneCode(phone);
      if (!mounted) return;
      setState(() {
        _phoneForCode = phone;
        _codeController.clear();
      });
      _startCooldown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
    } catch (error) {
      if (mounted) _showError(error, verifying: false);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_isBusy || !_hasCode || !_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authStateProvider.notifier)
          .verifyPhoneCode(
            phone: _phoneForCode!,
            code: _codeController.text.trim(),
          );
      if (!mounted) return;
      TextInput.finishAutofillContext();
      context.go('/');
    } catch (error) {
      if (mounted) _showError(error, verifying: true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _changeNumber() {
    if (_isBusy) return;
    setState(() {
      _phoneForCode = null;
      _codeController.clear();
      _errorMessage = null;
    });
    // Keep the resend cooldown when returning to the number entry form.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _phoneFocus.requestFocus();
    });
  }

  void _back() {
    if (_isBusy) return;
    FocusScope.of(context).unfocus();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(_phoneCodeCooldownProvider);
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(22) > 36;
    final horizontalPadding = MediaQuery.sizeOf(context).width < 360
        ? 20.0
        : 24.0;
    final callingCode = PhoneCountryNumber.callingCodeFor(_countryCode)!;
    final labelStyle = AppTextStyles.bodySmall.copyWith(
      fontWeight: FontWeight.w500,
      color: colors.onSurface,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.surface,
        toolbarHeight: largeText ? 112 : 64,
        titleSpacing: 8,
        title: const Text(
          'Sign in with phone',
          style: AppTextStyles.heading2,
          maxLines: 2,
        ),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _isBusy ? null : _back,
          icon: const Icon(Icons.arrow_back_outlined),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_hasCode) ...[
                        Text(
                          'We will send you a verification code by SMS.',
                          style: AppTextStyles.body.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        PhoneCountryPicker(
                          countryCode: _countryCode,
                          onChanged: _selectCountry,
                          enabled: !_isBusy,
                        ),
                        const SizedBox(height: 20),
                        AppTextField(
                          key: const ValueKey('phone-number-entry'),
                          label: 'Phone number',
                          labelStyle: labelStyle,
                          controller: _phoneController,
                          focusNode: _phoneFocus,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          hint: _countryCode == 'PH'
                              ? '912 345 6789'
                              : 'Phone number',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Text(
                              callingCode,
                              style: AppTextStyles.bodyMedium,
                            ),
                          ),
                          enabled: !_isBusy,
                          onChanged: _clearError,
                          onFieldSubmitted: (_) => _sendCode(),
                          validator: _validatePhone,
                        ),
                      ] else ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            'Enter the code sent to $_phoneForCode.',
                            style: AppTextStyles.body.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _isBusy ? null : _changeNumber,
                            child: const Text('Change phone number'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          key: const ValueKey('phone-code-entry'),
                          label: 'Verification code',
                          labelStyle: labelStyle,
                          controller: _codeController,
                          focusNode: _codeFocus,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          hint: 'Enter your SMS code',
                          prefixIcon: const Icon(Icons.sms_outlined, size: 20),
                          enabled: !_isBusy,
                          onChanged: _clearError,
                          onFieldSubmitted: (_) => _verifyCode(),
                          validator: (value) {
                            final code = value?.trim() ?? '';
                            if (code.isEmpty) {
                              return 'Enter the code from your SMS';
                            }
                            if (!RegExp(r'^\d{6,10}$').hasMatch(code)) {
                              return 'Enter the complete verification code from your SMS';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_errorMessage != null) ...[
                        Semantics(
                          key: _feedbackKey,
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.errorContainer,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: colors.onErrorContainer,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: AppTextStyles.body.copyWith(
                                      color: colors.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      AppButton(
                        label: _hasCode ? 'Verify and sign in' : 'Send code',
                        loadingLabel: _hasCode
                            ? 'Verifying code...'
                            : 'Sending code...',
                        onPressed: _hasCode
                            ? (_sending ? null : _verifyCode)
                            : (_secondsRemaining > 0 ? null : _sendCode),
                        isLoading: _hasCode ? _verifying : _sending,
                        width: double.infinity,
                      ),
                      if (_hasCode) ...[
                        const SizedBox(height: 12),
                        AppButton(
                          label: _secondsRemaining > 0
                              ? 'Resend code in ${_secondsRemaining}s'
                              : 'Resend code',
                          loadingLabel: 'Sending code...',
                          isOutlined: true,
                          isLoading: _sending,
                          onPressed: _isBusy || _secondsRemaining > 0
                              ? null
                              : _sendCode,
                          width: double.infinity,
                        ),
                      ] else if (_secondsRemaining > 0) ...[
                        const SizedBox(height: 12),
                        Text(
                          'You can request another code in ${_secondsRemaining}s.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _isBusy ? null : _back,
                        child: const Text('Back to sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

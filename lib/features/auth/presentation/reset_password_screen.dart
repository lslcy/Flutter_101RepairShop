import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/validation/password_policy.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/password_requirements.dart';
import '../data/auth_flow_controller.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _feedbackKey = GlobalKey();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  bool _showPasswordErrors = false;
  bool _isLeaving = false;
  String? _errorMessage;

  bool get _isBusy => _isSaving || _isLeaving;
  bool get _passwordIsValid =>
      PasswordPolicy.validate(_passwordController.text) == null;
  bool get _passwordsMatch =>
      _passwordIsValid &&
      _confirmController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text;

  @override
  void initState() {
    super.initState();
    _passwordFocus.addListener(_onPasswordFocusChanged);
    _passwordController.addListener(_onPasswordsChanged);
    _confirmController.addListener(_onPasswordsChanged);
  }

  void _onPasswordFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _passwordFocus.removeListener(_onPasswordFocusChanged);
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _onPasswordsChanged() => setState(() => _errorMessage = null);

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

  void _showError(String message) {
    setState(() => _errorMessage = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final feedbackContext = _feedbackKey.currentContext;
      if (mounted && feedbackContext != null) _reveal(feedbackContext);
    });
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (error is AuthException && error.code == 'same_password') {
      return 'Choose a password that is different from your current password.';
    }
    if (message.contains('same password') ||
        message.contains('different from the old password')) {
      return 'Choose a password that is different from your current password.';
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (message.contains('network') ||
        message.contains('socket') ||
        message.contains('timeout') ||
        message.contains('failed host lookup')) {
      return 'We could not connect. Check your internet connection and try again.';
    }
    if (error is AuthException && error.code == 'weak_password') {
      return 'This password was not accepted. ${PasswordPolicy.requirementsMessage}';
    }
    return 'We could not save your password. Please try again.';
  }

  Future<void> _savePassword() async {
    if (_isBusy) return;
    setState(() => _showPasswordErrors = true);
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final field = invalid.first.widget as TextFormField;
      (field.controller == _passwordController ? _passwordFocus : _confirmFocus)
          .requestFocus();
      _reveal(invalid.first.context);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authFlowProvider).updatePassword(_passwordController.text);
      if (!mounted) return;
      TextInput.finishAutofillContext();
      _passwordController.clear();
      _confirmController.clear();
    } catch (error) {
      if (!mounted) return;
      if (ref.read(authFlowProvider).stage != PasswordRecoveryStage.invalid) {
        _showError(_friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _leaveRecovery(String route) async {
    if (_isBusy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLeaving = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authFlowProvider).abandonRecovery();
      if (mounted) context.go(route);
    } catch (_) {
      if (!mounted) return;
      _showError('We could not close this reset session. Please try again.');
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  void _continue() {
    if (_isBusy) return;
    ref.read(authFlowProvider).finishRecovery();
    if (mounted) context.go('/');
  }

  Widget _feedback() {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: _feedbackKey,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colors.onErrorContainer, size: 22),
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
    );
  }

  Widget _passwordFeedback({required bool isMet, required String label}) {
    final theme = Theme.of(context);
    final color = isMet
        ? theme.brightness == Brightness.dark
              ? const Color(0xFF6EE7B7)
              : const Color(0xFF047857)
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        liveRegion: true,
        label: label,
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(
              isMet ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordForm() {
    final labelStyle = AppTextStyles.bodySmall.copyWith(
      fontWeight: FontWeight.w500,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'New password',
              labelStyle: labelStyle,
              hint: 'Create a new password',
              controller: _passwordController,
              focusNode: _passwordFocus,
              enabled: !_isBusy,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
              validator: PasswordPolicy.validate,
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: _isBusy
                    ? null
                    : () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
              ),
            ),
            PasswordRequirements(
              password: _passwordController.text,
              showErrors: _showPasswordErrors,
              isEditing: _passwordFocus.hasFocus,
            ),
            const SizedBox(height: 20),
            AppTextField(
              label: 'Confirm password',
              labelStyle: labelStyle,
              hint: 'Re-enter your new password',
              controller: _confirmController,
              focusNode: _confirmFocus,
              enabled: !_isBusy,
              obscureText: _obscureConfirm,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _savePassword(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
              suffixIcon: IconButton(
                tooltip: _obscureConfirm
                    ? 'Show confirmed password'
                    : 'Hide confirmed password',
                onPressed: _isBusy
                    ? null
                    : () => setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
              ),
            ),
            if (_passwordsMatch)
              _passwordFeedback(isMet: true, label: 'Passwords match'),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              _feedback(),
              const SizedBox(height: 16),
            ],
            AppButton(
              label: 'Save new password',
              loadingLabel: 'Saving password...',
              onPressed: _isLeaving ? null : _savePassword,
              isLoading: _isSaving,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusContent({required bool complete, required bool invalid}) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              complete
                  ? Icons.check_circle_outline
                  : Icons.mark_email_read_outlined,
              size: 28,
              color: colors.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            complete
                ? 'Password updated'
                : invalid
                ? 'This link is no longer valid'
                : 'Open your password reset link',
            style: AppTextStyles.heading2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          complete
              ? 'Your new password is saved. You can continue to your account.'
              : invalid
              ? 'Request a new link, then open the most recent email.'
              : 'Use the link in your email to choose a new password.',
          style: AppTextStyles.body.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        if (_errorMessage != null) ...[_feedback(), const SizedBox(height: 16)],
        AppButton(
          label: complete ? 'Continue' : 'Request a new link',
          loadingLabel: 'Please wait...',
          onPressed: complete
              ? _continue
              : () => _leaveRecovery('/forgot-password'),
          isLoading: _isBusy,
          width: double.infinity,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(authFlowProvider);
    final complete = flow.stage == PasswordRecoveryStage.complete;
    final ready = flow.canResetPassword;
    final invalid =
        flow.stage == PasswordRecoveryStage.invalid ||
        (flow.stage == PasswordRecoveryStage.ready && !flow.canResetPassword);
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(22) > 36;
    final horizontalPadding = MediaQuery.sizeOf(context).width < 360
        ? 20.0
        : 24.0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isBusy) _leaveRecovery('/login');
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: colors.surface,
          toolbarHeight: largeText ? 112 : 64,
          titleSpacing: 8,
          title: const Text(
            'Reset password',
            style: AppTextStyles.heading2,
            maxLines: 2,
          ),
          leading: IconButton(
            tooltip: 'Back to sign in',
            icon: const Icon(Icons.arrow_back_outlined),
            onPressed: _isBusy ? null : () => _leaveRecovery('/login'),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (ready)
                      _passwordForm()
                    else
                      _statusContent(complete: complete, invalid: invalid),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isBusy
                          ? null
                          : () => _leaveRecovery('/login'),
                      child: const Text('Back to sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

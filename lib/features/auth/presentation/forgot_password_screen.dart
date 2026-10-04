import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/auth_repository.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail.trim();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    if (_isLoading) return;
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      _emailFocus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !invalid.first.mounted) return;
        Scrollable.ensureVisible(
          invalid.first.context,
          alignment: 0.2,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
        );
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authStateProvider.notifier)
          .resetPassword(_emailController.text.trim());
      if (mounted) setState(() => _emailSent = true);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().toLowerCase();
      final code = error is AuthException ? error.code : null;
      final limited =
          code == 'over_email_send_rate_limit' ||
          code == 'over_request_rate_limit' ||
          message.contains('too many requests') ||
          message.contains('rate limit');
      final deliveryUnavailable =
          message.contains('not authorized') ||
          message.contains('sending recovery email') ||
          message.contains('smtp');
      setState(
        () => _errorMessage = limited
            ? 'Too many requests. Please wait a moment and try again.'
            : deliveryUnavailable
            ? 'Password reset email is unavailable right now. Please try again later.'
            : 'We could not send the reset link. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: _isLoading
              ? null
              : () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/login', extra: _emailController.text.trim());
                  }
                },
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _emailSent ? _buildSuccessView() : _buildFormView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView() {
    final colors = Theme.of(context).colorScheme;
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reset your password', style: AppTextStyles.heading1),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Enter the email you used to create your account. We’ll send you a reset link.',
              style: AppTextStyles.body.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: 'Email address',
              labelStyle: AppTextStyles.bodySmall.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              hint: 'you@example.com',
              controller: _emailController,
              focusNode: _emailFocus,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) => _handleReset(),
              prefixIcon: const Icon(Icons.email_outlined, size: 20),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Enter your email address';
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_errorMessage != null) ...[
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: colors.onErrorContainer,
                        size: 22,
                      ),
                      const SizedBox(width: AppSpacing.sm),
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
              const SizedBox(height: AppSpacing.md),
            ],
            AppButton(
              label: 'Send reset link',
              loadingLabel: 'Sending reset link…',
              onPressed: _handleReset,
              isLoading: _isLoading,
              width: double.infinity,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _isLoading
                  ? null
                  : () => context.go(
                      '/login',
                      extra: _emailController.text.trim(),
                    ),
              child: const Text('Back to sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Icon(
                Icons.mark_email_read_outlined,
                size: 32,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Check your email', style: AppTextStyles.heading1),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'If an account uses ${_emailController.text.trim()}, a password reset link will arrive shortly.',
            style: AppTextStyles.body.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Open the latest link on this device. Check your spam folder if it does not arrive.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Back to sign in',
            onPressed: () =>
                context.go('/login', extra: _emailController.text.trim()),
            width: double.infinity,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () {
              setState(() {
                _emailSent = false;
                _errorMessage = null;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _emailFocus.requestFocus();
              });
            },
            child: const Text('Use a different email'),
          ),
        ],
      ),
    );
  }
}

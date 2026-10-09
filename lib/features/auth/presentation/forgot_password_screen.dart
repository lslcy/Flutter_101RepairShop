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
  final _scrollController = ScrollController();
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
    _scrollController.dispose();
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
      if (mounted) {
        setState(() => _emailSent = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      }
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
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 360 ? 20 : AppSpacing.lg,
            AppSpacing.sm,
            MediaQuery.sizeOf(context).width < 360 ? 20 : AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
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
    final email = _emailController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Container(
            key: const ValueKey('reset-email-confirmation'),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.mark_email_read_outlined,
                          size: 24,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Check your email',
                          style: AppTextStyles.heading2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'If an account uses this email, a password reset link will arrive shortly.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  email,
                  key: const ValueKey('reset-email-address'),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.open_in_new_outlined,
                color: colors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Open the latest email',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Use the link on this device to reset your password.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'No email yet? Check your spam folder.',
          style: AppTextStyles.bodySmall.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Back to sign in',
          onPressed: () => context.go('/login', extra: email),
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
    );
  }
}

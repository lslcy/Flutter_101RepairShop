import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/auth_flow_controller.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _feedbackKey = GlobalKey();
  final _googleFeedbackKey = GlobalKey();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLaunching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail.trim();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _reveal(BuildContext fieldContext, {double alignment = 0.2}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !fieldContext.mounted) return;
      Scrollable.ensureVisible(
        fieldContext,
        alignment: alignment,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
      );
    });
  }

  bool get _isBusy =>
      _isLoading ||
      _isGoogleLaunching ||
      ref.read(authFlowProvider).isGoogleSignInPending;

  void _clearError(String _) {
    if (_errorMessage != null) setState(() => _errorMessage = null);
    final flow = ref.read(authFlowProvider);
    if (flow.googleSignInError != null) flow.cancelGoogleSignIn();
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isBusy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isGoogleLaunching = true;
      _errorMessage = null;
    });
    try {
      final launched = await ref
          .read(authStateProvider.notifier)
          .signInWithGoogle();
      if (!mounted) return;
      if (!launched) {
        setState(() {
          _errorMessage = 'We could not open Google sign-in. Please try again.';
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final feedbackContext = launched
            ? _googleFeedbackKey.currentContext
            : _feedbackKey.currentContext;
        if (mounted && feedbackContext != null) {
          _reveal(feedbackContext, alignment: 0);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _getFriendlyError(error.toString()));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final feedbackContext = _feedbackKey.currentContext;
        if (mounted && feedbackContext != null) {
          _reveal(feedbackContext, alignment: 0);
        }
      });
    } finally {
      if (mounted) setState(() => _isGoogleLaunching = false);
    }
  }

  Future<void> _handleLogin() async {
    if (_isBusy) return;
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final field = invalid.first.widget as TextFormField;
      (field.controller == _emailController ? _emailFocus : _passwordFocus)
          .requestFocus();
      _reveal(invalid.first.context);
      return;
    }
    FocusScope.of(context).unfocus();
    ref.read(authFlowProvider).cancelGoogleSignIn();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authStateProvider.notifier)
          .signIn(_emailController.text.trim(), _passwordController.text);
      if (!mounted) return;
      TextInput.finishAutofillContext();
      context.go('/');
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _getFriendlyError(error.toString()));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final feedbackContext = _feedbackKey.currentContext;
        if (mounted && feedbackContext != null) {
          _reveal(feedbackContext, alignment: 0);
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getFriendlyError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('provider is not enabled') ||
        lower.contains('unsupported provider') ||
        lower.contains('provider_disabled') ||
        lower.contains('provider_not_enabled')) {
      return 'Google sign-in is not available yet. Please use another sign-in method.';
    }
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid_credentials')) {
      return 'Incorrect email or password. Check your details and try again.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Confirm your email using the link in your inbox, then sign in.';
    }
    if (lower.contains('too many requests') || lower.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('timeout')) {
      return 'We could not connect. Check your internet connection and try again.';
    }
    return 'We could not sign you in. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final flow = ref.watch(authFlowProvider);
    final isBusy =
        _isLoading || _isGoogleLaunching || flow.isGoogleSignInPending;
    final errorMessage = _errorMessage ?? flow.googleSignInError;
    ref.listen<String?>(
      authFlowProvider.select((controller) => controller.googleSignInError),
      (previous, next) {
        if (next == null || next == previous) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final feedbackContext = _feedbackKey.currentContext;
          if (mounted && feedbackContext != null) {
            _reveal(feedbackContext, alignment: 0);
          }
        });
      },
    );
    final largeText = MediaQuery.textScalerOf(context).scale(22) > 36;
    final horizontalPadding = MediaQuery.sizeOf(context).width < 360
        ? 20.0
        : 24.0;
    final fieldLabelStyle = AppTextStyles.bodySmall.copyWith(
      fontWeight: FontWeight.w500,
      color: colors.onSurface,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.surface,
        toolbarHeight: largeText ? 112 : 64,
        titleSpacing: 8,
        title: const Text(
          'Welcome back',
          style: AppTextStyles.heading2,
          maxLines: 2,
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: isBusy
              ? null
              : () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/welcome');
                  }
                },
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
                      if (errorMessage != null) ...[
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
                                    errorMessage,
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
                      AppTextField(
                        label: 'Email address',
                        labelStyle: fieldLabelStyle,
                        hint: 'you@example.com',
                        controller: _emailController,
                        focusNode: _emailFocus,
                        enabled: !isBusy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        onChanged: _clearError,
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        prefixIcon: const Icon(Icons.mail_outline, size: 20),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return 'Enter your email address';
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(email)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      AppTextField(
                        label: 'Password',
                        labelStyle: fieldLabelStyle,
                        hint: 'Enter your password',
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        enabled: !isBusy,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onChanged: _clearError,
                        onFieldSubmitted: (_) => _handleLogin(),
                        prefixIcon: const Icon(Icons.lock_outlined, size: 20),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: isBusy
                              ? null
                              : () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                        ),
                        // Existing accounts may predate the new-password rules.
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your password'
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: isBusy
                              ? null
                              : () {
                                  FocusScope.of(context).unfocus();
                                  context.go(
                                    '/forgot-password',
                                    extra: _emailController.text.trim(),
                                  );
                                },
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppButton(
                        label: 'Sign in',
                        loadingLabel: 'Signing in...',
                        onPressed: isBusy ? null : _handleLogin,
                        isLoading: _isLoading,
                        width: double.infinity,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(child: Divider(height: 1)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Or',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider(height: 1)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      AppButton(
                        label: 'Continue with Google',
                        leading: Image.asset(
                          'assets/images/google_g.png',
                          width: 20,
                          height: 20,
                          excludeFromSemantics: true,
                        ),
                        loadingLabel: 'Opening Google...',
                        onPressed: isBusy ? null : _handleGoogleSignIn,
                        isLoading: _isGoogleLaunching,
                        isOutlined: true,
                        width: double.infinity,
                      ),
                      if (flow.isGoogleSignInPending &&
                          !_isGoogleLaunching) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          key: _googleFeedbackKey,
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.open_in_new_outlined,
                                      color: colors.onPrimaryContainer,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Finish signing in with Google in your browser.',
                                        style: AppTextStyles.body.copyWith(
                                          color: colors.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                TextButton(
                                  onPressed: _isGoogleLaunching
                                      ? null
                                      : () {
                                          ref
                                              .read(authFlowProvider)
                                              .cancelGoogleSignIn();
                                        },
                                  style: TextButton.styleFrom(
                                    foregroundColor: colors.onPrimaryContainer,
                                    minimumSize: const Size(48, 48),
                                  ),
                                  child: const Text(
                                    'Use another sign-in method',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      AppButton(
                        label: 'Continue with phone',
                        icon: Icons.phone_outlined,
                        onPressed: isBusy
                            ? null
                            : () {
                                FocusScope.of(context).unfocus();
                                context.go('/phone-sign-in');
                              },
                        isOutlined: true,
                        width: double.infinity,
                      ),
                      const SizedBox(height: 24),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "Don't have an account?",
                            style: AppTextStyles.bodySmall.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed: isBusy
                                ? null
                                : () => context.go('/register'),
                            child: const Text('Create account'),
                          ),
                        ],
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

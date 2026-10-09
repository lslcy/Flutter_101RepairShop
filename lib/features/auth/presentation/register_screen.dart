import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/validation/password_policy.dart';
import '../../../core/validation/customer_identity.dart';
import '../../../core/utils/account_errors.dart';
import '../../../core/utils/form_validation.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/address_input.dart';
import '../../../core/widgets/password_requirements.dart';
import '../data/auth_repository.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _feedbackKey = GlobalKey();
  final _phoneFieldKey = GlobalKey();
  bool _showPhoneField = false;
  // Keep this order aligned with the visual form, including responsive name fields.
  late final _fieldFocus = <TextEditingController, FocusNode>{
    _firstNameController: FocusNode(),
    _lastNameController: FocusNode(),
    _emailController: FocusNode(),
    _phoneController: FocusNode(),
    _addressController: FocusNode(),
    _passwordController: FocusNode(),
    _confirmPasswordController: FocusNode(),
  };
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _showPasswordErrors = false;
  bool _showMatchStatus = false;
  bool _passwordsMatch = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fieldFocus[_passwordController]!.addListener(_onPasswordFocusChanged);
    _passwordController.addListener(_checkPasswordMatch);
    _confirmPasswordController.addListener(_checkPasswordMatch);
  }

  void _checkPasswordMatch() {
    setState(() {
      _showMatchStatus = _confirmPasswordController.text.isNotEmpty;
      _passwordsMatch =
          PasswordPolicy.validate(_passwordController.text) == null &&
          _passwordController.text == _confirmPasswordController.text;
    });
  }

  void _onPasswordFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _fieldFocus[_passwordController]!.removeListener(_onPasswordFocusChanged);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (final node in _fieldFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  String _getFriendlyError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('user already registered') ||
        lower.contains('already been registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (lower.contains('weak password') || lower.contains('password')) {
      return PasswordPolicy.requirementsMessage;
    }
    if (lower.contains('invalid email') ||
        lower.contains('unable to validate')) {
      return 'Please enter a valid email address.';
    }
    if (lower.contains('rate limit') || lower.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('timeout')) {
      return 'No internet connection. Please check your network.';
    }
    return 'Registration failed. Please try again.';
  }

  Future<void> _handleRegister() async {
    if (_isLoading) return;
    setState(() => _showPasswordErrors = true);
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final firstInvalid = firstInvalidFormField(invalid);
      firstInvalid.context
          .findAncestorWidgetOfExactType<AppTextField>()
          ?.focusNode
          ?.requestFocus();
      _reveal(firstInvalid.context);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final needsConfirmation = await ref
          .read(authStateProvider.notifier)
          .signUp(
            email: CustomerIdentity.normalizeEmail(_emailController.text),
            password: _passwordController.text,
            firstName: CustomerIdentity.normalizeName(
              _firstNameController.text,
            ),
            lastName: CustomerIdentity.normalizeName(_lastNameController.text),
            phoneNo: CustomerIdentity.normalizeOptionalPhone(
              _phoneController.text,
            ),
            address: _addressController.text.trim(),
          );
      TextInput.finishAutofillContext();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            needsConfirmation
                ? 'Account created! Check your email to confirm your account, then sign in.'
                : 'Account created! You can now sign in.',
          ),
          duration: const Duration(seconds: 7),
          backgroundColor: AppColors.primary,
        ),
      );
      context.go('/login');
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = friendlyAccountError(
          error,
          fallback: _getFriendlyError(error.toString()),
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final feedbackContext = _feedbackKey.currentContext;
        if (mounted && feedbackContext != null) _reveal(feedbackContext);
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  TextStyle get _fieldLabelStyle => AppTextStyles.bodySmall.copyWith(
    fontWeight: FontWeight.w500,
    color: Theme.of(context).colorScheme.onSurface,
  );

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colors.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: AppTextStyles.heading3)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }

  Widget _nameFields() {
    final firstName = AppTextField(
      label: 'First name',
      labelStyle: _fieldLabelStyle,
      hint: 'First name',
      controller: _firstNameController,
      focusNode: _fieldFocus[_firstNameController],
      enabled: !_isLoading,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => _fieldFocus[_lastNameController]!.requestFocus(),
      autofillHints: const [AutofillHints.givenName],
      validator: (value) =>
          CustomerIdentity.validateName(value, fieldName: 'first name'),
    );
    final lastName = AppTextField(
      label: 'Last name',
      labelStyle: _fieldLabelStyle,
      hint: 'Last name',
      controller: _lastNameController,
      focusNode: _fieldFocus[_lastNameController],
      enabled: !_isLoading,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => _fieldFocus[_emailController]!.requestFocus(),
      autofillHints: const [AutofillHints.familyName],
      validator: (value) =>
          CustomerIdentity.validateName(value, fieldName: 'last name'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(14) > 18) {
          return Column(
            children: [firstName, const SizedBox(height: 16), lastName],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: firstName),
            const SizedBox(width: 16),
            Expanded(child: lastName),
          ],
        );
      },
    );
  }

  void _revealPhoneField() {
    setState(() => _showPhoneField = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fieldFocus[_phoneController]!.requestFocus();
      final fieldContext = _phoneFieldKey.currentContext;
      if (fieldContext != null) _reveal(fieldContext);
    });
  }

  Widget _detailsSection() => _section(
    title: 'Your details',
    icon: Icons.person_outline,
    children: [
      _nameFields(),
      const SizedBox(height: 16),
      AppTextField(
        label: 'Email address',
        labelStyle: _fieldLabelStyle,
        hint: 'you@example.com',
        controller: _emailController,
        focusNode: _fieldFocus[_emailController],
        enabled: !_isLoading,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onFieldSubmitted: (_) =>
            _fieldFocus[_showPhoneField
                    ? _phoneController
                    : _addressController]!
                .requestFocus(),
        autofillHints: const [AutofillHints.email],
        prefixIcon: const Icon(Icons.mail_outline, size: 20),
        validator: CustomerIdentity.validateEmail,
      ),
      if (_showPhoneField) ...[
        const SizedBox(height: 16),
        AppTextField(
          key: _phoneFieldKey,
          label: 'Phone number (optional)',
          labelStyle: _fieldLabelStyle,
          hint: 'e.g. 0917 123 4567',
          controller: _phoneController,
          focusNode: _fieldFocus[_phoneController],
          enabled: !_isLoading,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) =>
              _fieldFocus[_addressController]!.requestFocus(),
          autofillHints: const [AutofillHints.telephoneNumber],
          prefixIcon: const Icon(Icons.phone_outlined, size: 20),
          validator: CustomerIdentity.validateOptionalPhone,
        ),
      ] else ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _isLoading ? null : _revealPhoneField,
            icon: const Icon(Icons.add_outlined, size: 20),
            label: const Text('Add phone number (optional)'),
          ),
        ),
      ],
    ],
  );

  Widget _securitySection() {
    final matchColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF6EE7B7)
        : const Color(0xFF047857);
    return _section(
      title: 'Secure your account',
      icon: Icons.lock_outlined,
      children: [
        AppTextField(
          label: 'Password',
          labelStyle: _fieldLabelStyle,
          hint: 'Create a password',
          controller: _passwordController,
          focusNode: _fieldFocus[_passwordController],
          enabled: !_isLoading,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) =>
              _fieldFocus[_confirmPasswordController]!.requestFocus(),
          autofillHints: const [AutofillHints.newPassword],
          suffixIcon: IconButton(
            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
            onPressed: _isLoading
                ? null
                : () => setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
          ),
          validator: PasswordPolicy.validate,
        ),
        PasswordRequirements(
          password: _passwordController.text,
          showErrors: _showPasswordErrors,
          isEditing: _fieldFocus[_passwordController]!.hasFocus,
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Confirm password',
          labelStyle: _fieldLabelStyle,
          hint: 'Re-enter your password',
          controller: _confirmPasswordController,
          focusNode: _fieldFocus[_confirmPasswordController],
          enabled: !_isLoading,
          obscureText: _obscureConfirm,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleRegister(),
          autofillHints: const [AutofillHints.newPassword],
          suffixIcon: IconButton(
            tooltip: _obscureConfirm
                ? 'Show confirmed password'
                : 'Hide confirmed password',
            onPressed: _isLoading
                ? null
                : () => setState(() => _obscureConfirm = !_obscureConfirm),
            icon: Icon(
              _obscureConfirm
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Confirm your password';
            if (value != _passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
        if (_showMatchStatus && _passwordsMatch)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: matchColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Passwords match',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: matchColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionDivider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Divider(height: 1),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(22) > 36;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.surface,
        toolbarHeight: largeText ? 112 : 64,
        titleSpacing: 8,
        title: const Text(
          'Create account',
          style: AppTextStyles.heading2,
          maxLines: 2,
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: _isLoading
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
            MediaQuery.sizeOf(context).width < 360 ? 20 : 24,
            20,
            MediaQuery.sizeOf(context).width < 360 ? 20 : 24,
            32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _detailsSection(),
                      _sectionDivider(),
                      _section(
                        title: 'Your address',
                        icon: Icons.location_on_outlined,
                        children: [
                          AddressInput(
                            controller: _addressController,
                            focusNode: _fieldFocus[_addressController],
                            labelStyle: _fieldLabelStyle,
                            enabled: !_isLoading,
                          ),
                        ],
                      ),
                      _sectionDivider(),
                      _securitySection(),
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
                        label: 'Create account',
                        loadingLabel: 'Creating account…',
                        icon: Icons.person_add_alt_1_outlined,
                        onPressed: _handleRegister,
                        isLoading: _isLoading,
                        width: double.infinity,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Already have an account?',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => context.go('/login'),
                            child: const Text('Sign in'),
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

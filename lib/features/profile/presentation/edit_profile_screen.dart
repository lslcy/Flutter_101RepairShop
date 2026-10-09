import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/account_errors.dart';
import '../../../core/utils/form_validation.dart';
import '../../../core/validation/customer_identity.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/address_input.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../data/customer_repository.dart';
import '../../shared/models/customer.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  late final _fieldFocus = <TextEditingController, FocusNode>{
    _firstNameController: FocusNode(),
    _lastNameController: FocusNode(),
    _emailController: FocusNode(),
    _phoneController: FocusNode(),
    _addressController: FocusNode(),
  };
  Customer? _customer;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final customer = await ref
          .read(customerRepositoryProvider)
          .getCurrentCustomer()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _customer = customer;
        if (customer != null) {
          _firstNameController.text = customer.firstName ?? '';
          _lastNameController.text = customer.lastName ?? '';
          _emailController.text = customer.email ?? '';
          _phoneController.text = customer.phoneNo ?? '';
          _addressController.text = customer.address ?? '';
        } else {
          _loadError = 'Your profile is unavailable. Please try again.';
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'We couldn’t load your details. Check your connection and try again.';
      });
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving || _customer == null) {
      return;
    }
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final firstInvalid = firstInvalidFormField(invalid);
      firstInvalid.context
          .findAncestorWidgetOfExactType<AppTextField>()
          ?.focusNode
          ?.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !firstInvalid.mounted) return;
        Scrollable.ensureVisible(
          firstInvalid.context,
          alignment: 0.15,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
        );
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    try {
      final updated = Customer(
        id: _customer!.id,
        authId: _customer!.authId,
        firstName: CustomerIdentity.normalizeName(_firstNameController.text),
        lastName: CustomerIdentity.normalizeName(_lastNameController.text),
        email: CustomerIdentity.normalizeEmail(_emailController.text),
        phoneNo: CustomerIdentity.normalizeOptionalPhone(_phoneController.text),
        address: _addressController.text.trim(),
        profilePicture: _customer!.profilePicture,
        createdAt: _customer!.createdAt,
        updatedAt: _customer!.updatedAt,
      );
      await ref.read(customerRepositoryProvider).updateProfile(updated);
      if (!mounted) return;
      ref.read(customerProfileRevisionProvider.notifier).state++;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your profile and address have been saved.'),
        ),
      );
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/profile');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyAccountError(
              error,
              fallback: 'Could not save your details. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    for (final node in _fieldFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Personal information', style: AppTextStyles.heading2),
      ),
      body: SafeArea(
        child: _isLoading
            ? const ShimmerLoading(
                label: 'Loading your personal information...',
              )
            : SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: _loadError != null
                        ? AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(_loadError!, style: AppTextStyles.body),
                                const SizedBox(height: AppSpacing.md),
                                AppButton(
                                  label: 'Try again',
                                  icon: Icons.refresh_outlined,
                                  onPressed: _loadProfile,
                                ),
                              ],
                            ),
                          )
                        : AutofillGroup(
                            child: Form(
                              key: _formKey,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Keep your details up to date',
                                    style: AppTextStyles.heading3,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    'Help the repair team contact you about your appointments.',
                                    style: AppTextStyles.body.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  AppCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _sectionTitle(
                                          Icons.person_outline,
                                          'Contact details',
                                        ),
                                        const SizedBox(height: AppSpacing.lg),
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            final first = AppTextField(
                                              label: 'First name',
                                              hint: 'First name',
                                              controller: _firstNameController,
                                              focusNode:
                                                  _fieldFocus[_firstNameController],
                                              enabled: !_isSaving,
                                              textCapitalization:
                                                  TextCapitalization.words,
                                              textInputAction:
                                                  TextInputAction.next,
                                              autofillHints: const [
                                                AutofillHints.givenName,
                                              ],
                                              validator: (value) =>
                                                  CustomerIdentity.validateName(
                                                    value,
                                                    fieldName: 'first name',
                                                  ),
                                            );
                                            final last = AppTextField(
                                              label: 'Last name',
                                              hint: 'Last name',
                                              controller: _lastNameController,
                                              focusNode:
                                                  _fieldFocus[_lastNameController],
                                              enabled: !_isSaving,
                                              textCapitalization:
                                                  TextCapitalization.words,
                                              textInputAction:
                                                  TextInputAction.next,
                                              autofillHints: const [
                                                AutofillHints.familyName,
                                              ],
                                              validator: (value) =>
                                                  CustomerIdentity.validateName(
                                                    value,
                                                    fieldName: 'last name',
                                                  ),
                                            );
                                            if (constraints.maxWidth < 420) {
                                              return Column(
                                                children: [
                                                  first,
                                                  const SizedBox(
                                                    height: AppSpacing.md,
                                                  ),
                                                  last,
                                                ],
                                              );
                                            }
                                            return Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(child: first),
                                                const SizedBox(
                                                  width: AppSpacing.md,
                                                ),
                                                Expanded(child: last),
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        AppTextField(
                                          label: 'Contact email',
                                          hint: 'Email address',
                                          helperText: 'Updating this contact email does not change your sign-in email.',
                                          controller: _emailController,
                                          focusNode:
                                              _fieldFocus[_emailController],
                                          validator: (value) =>
                                              CustomerIdentity.validateEmail(
                                                value,
                                                required: false,
                                              ),
                                          enabled: !_isSaving,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          textInputAction: TextInputAction.next,
                                          autofillHints: const [
                                            AutofillHints.email,
                                          ],
                                          prefixIcon: const Icon(
                                            Icons.email_outlined,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        AppTextField(
                                          label: 'Phone number (optional)',
                                          hint: 'e.g. 0917 123 4567',
                                          controller: _phoneController,
                                          focusNode:
                                              _fieldFocus[_phoneController],
                                          validator: CustomerIdentity
                                              .validateOptionalPhone,
                                          enabled: !_isSaving,
                                          keyboardType: TextInputType.phone,
                                          textInputAction: TextInputAction.next,
                                          autofillHints: const [
                                            AutofillHints.telephoneNumber,
                                          ],
                                          prefixIcon: const Icon(
                                            Icons.phone_outlined,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  AppCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _sectionTitle(
                                          Icons.location_on_outlined,
                                          'Your address',
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        Text(
                                          'Save your address with your contact information.',
                                          style: AppTextStyles.body.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.lg),
                                        AddressInput(
                                          controller: _addressController,
                                          focusNode:
                                              _fieldFocus[_addressController],
                                          enabled: !_isSaving,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  AppButton(
                                    label: 'Save changes',
                                    loadingLabel: 'Saving changes...',
                                    icon: Icons.check_outlined,
                                    onPressed: _handleSave,
                                    isLoading: _isSaving,
                                    width: double.infinity,
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

  Widget _sectionTitle(IconData icon, String title) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colors.primary, size: 22),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: AppTextStyles.heading3)),
      ],
    );
  }
}

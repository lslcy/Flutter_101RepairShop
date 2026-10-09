import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/load_errors.dart';
import '../../../core/utils/account_errors.dart';
import '../../../core/validation/customer_identity.dart';
import '../../../core/widgets/address_input.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../data/auth_flow_controller.dart';

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _address = TextEditingController();
  final _firstFocus = FocusNode();
  final _lastFocus = FocusNode();
  final _addressFocus = FocusNode();
  bool _filled = false;
  bool _saving = false;
  bool _signingOut = false;
  String? _error;

  bool get _busy => _saving || _signingOut;

  @override
  void dispose() {
    for (final controller in [_first, _last, _address]) {
      controller.dispose();
    }
    for (final node in [_firstFocus, _lastFocus, _addressFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final controllers = [_first, _last, _address];
      final nodes = [_firstFocus, _lastFocus, _addressFocus];
      final firstInvalid =
          controllers
              .expand(
                (controller) => invalid.where(
                  (field) =>
                      field.widget is TextFormField &&
                      (field.widget as TextFormField).controller == controller,
                ),
              )
              .firstOrNull ??
          invalid.first;
      final widget = firstInvalid.widget;
      if (widget is TextFormField) {
        final index = controllers.indexOf(widget.controller!);
        if (index >= 0) nodes[index].requestFocus();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && firstInvalid.mounted) {
          Scrollable.ensureVisible(
            firstInvalid.context,
            alignment: 0.15,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
          );
        }
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authFlowProvider)
          .completeSignInProfile(
            firstName: CustomerIdentity.normalizeName(_first.text),
            lastName: CustomerIdentity.normalizeName(_last.text),
            address: _address.text,
          );
      TextInput.finishAutofillContext();
      if (mounted) context.go('/');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = friendlyAccountError(
            error,
            fallback: friendlyError(
              error,
              fallback: 'We could not save your details. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      await ref
          .read(authFlowProvider)
          .client
          .auth
          .signOut(scope: SignOutScope.local);
      if (mounted) context.go('/login');
    } catch (error) {
      // Local sign-out may complete even when remote logout cannot connect.
      if (!mounted) return;
      if (!ref.read(authFlowProvider).isLoggedIn) {
        context.go('/login');
      } else {
        setState(
          () => _error = friendlyError(
            error,
            fallback: 'We could not sign you out. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(authFlowProvider);
    final colors = Theme.of(context).colorScheme;
    final checking = flow.profileStage == SignInProfileStage.checking;
    final failed = flow.profileStage == SignInProfileStage.failed;
    if (!_filled && !checking && !failed) {
      final customer = flow.signInCustomer;
      final metadata = flow.client.auth.currentUser?.userMetadata;
      String? metadataText(String key) {
        final value = metadata?[key];
        return value is String && value.trim().isNotEmpty ? value : null;
      }

      String? nonBlank(String? value) =>
          value?.trim().isNotEmpty == true ? value : null;
      final fullName = (metadataText('full_name') ?? '').trim().split(
        RegExp(r'\s+'),
      );
      _first.text =
          nonBlank(customer?.firstName) ??
          metadataText('given_name') ??
          metadataText('first_name') ??
          fullName.first;
      _last.text =
          nonBlank(customer?.lastName) ??
          metadataText('family_name') ??
          metadataText('last_name') ??
          fullName.skip(1).join(' ');
      _address.text = customer?.address ?? metadataText('address') ?? '';
      _filled = true;
    }
    final message = failed
        ? friendlyError(
            flow.profileError ?? StateError('Profile unavailable'),
            fallback: 'We could not load your details. Please try again.',
          )
        : _error;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 30
              ? 112
              : 64,
          title: Text(
            'Complete your account',
            maxLines: 2,
            style: AppTextStyles.heading2,
          ),
        ),
        body: SafeArea(
          child: checking
              ? const ShimmerLoading(label: 'Checking your account...')
              : SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: AutofillGroup(
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!failed) ...[
                                AppTextField(
                                  label: 'First name',
                                  controller: _first,
                                  focusNode: _firstFocus,
                                  enabled: !_busy,
                                  autofillHints: const [
                                    AutofillHints.givenName,
                                  ],
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted: (_) =>
                                      _lastFocus.requestFocus(),
                                  validator: (value) =>
                                      CustomerIdentity.validateName(
                                        value,
                                        fieldName: 'first name',
                                        trailingPeriod: true,
                                      ),
                                ),
                                const SizedBox(height: 20),
                                AppTextField(
                                  label: 'Last name',
                                  controller: _last,
                                  focusNode: _lastFocus,
                                  enabled: !_busy,
                                  autofillHints: const [
                                    AutofillHints.familyName,
                                  ],
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted: (_) =>
                                      _addressFocus.requestFocus(),
                                  validator: (value) =>
                                      CustomerIdentity.validateName(
                                        value,
                                        fieldName: 'last name',
                                        trailingPeriod: true,
                                      ),
                                ),
                                const SizedBox(height: 20),
                                AddressInput(
                                  controller: _address,
                                  focusNode: _addressFocus,
                                  enabled: !_busy,
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 24),
                              ],
                              if (message != null) ...[
                                Semantics(
                                  liveRegion: true,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: colors.errorContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      message,
                                      style: AppTextStyles.body.copyWith(
                                        color: colors.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              AppButton(
                                label: failed
                                    ? 'Try again'
                                    : 'Save and continue',
                                loadingLabel: 'Saving details...',
                                isLoading: _saving,
                                width: double.infinity,
                                onPressed: _busy
                                    ? null
                                    : failed
                                    ? flow.retrySignInProfile
                                    : _save,
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _busy ? null : _signOut,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                child: Text(
                                  _signingOut
                                      ? 'Signing out...'
                                      : 'Use another account',
                                ),
                              ),
                            ],
                          ),
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

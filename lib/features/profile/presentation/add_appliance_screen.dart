import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/utils/load_errors.dart';
import '../data/customer_repository.dart';

class AddApplianceScreen extends ConsumerStatefulWidget {
  const AddApplianceScreen({super.key});

  @override
  ConsumerState<AddApplianceScreen> createState() => _AddApplianceScreenState();
}

class _AddApplianceScreenState extends ConsumerState<AddApplianceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _brandKey = GlobalKey();
  final _productKey = GlobalKey();
  final _brandFocus = FocusNode();
  final _productFocus = FocusNode();
  final _brandController = TextEditingController();
  final _productController = TextEditingController();
  final _modelController = TextEditingController();
  final _serialController = TextEditingController();
  String? _selectedCategory;
  String? _selectedSize;
  bool _isSaving = false;
  String? _saveError;

  @override
  void dispose() {
    _brandFocus.dispose();
    _productFocus.dispose();
    _brandController.dispose();
    _productController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    super.dispose();
  }

  void _showFirstInvalidField() {
    final invalidBrand = _brandController.text.trim().isEmpty;
    final focus = invalidBrand ? _brandFocus : _productFocus;
    final fieldKey = invalidBrand ? _brandKey : _productKey;
    focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || fieldKey.currentContext == null) return;
      Scrollable.ensureVisible(
        fieldKey.currentContext!,
        alignment: 0.15,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
      );
    });
  }

  Future<void> _handleSubmit() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) {
      _showFirstInvalidField();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await ref.read(customerRepositoryProvider).addAppliance({
        'brand': _brandController.text.trim(),
        'product': _productController.text.trim(),
        'model_no': _modelController.text.trim(),
        'serial_no': _serialController.text.trim(),
        'category': _selectedCategory,
        'appliance_size': _selectedSize,
      });
      if (!mounted) return;
      // Re-enable popping before returning from a successful save.
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Appliance added.')));
      context.pop();
    } catch (error) {
      if (!mounted) return;
      final message = friendlyError(
        error,
        fallback:
            'Could not add your appliance. Your details are still here. Please try again.',
      );
      setState(() => _saveError = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add appliance', style: AppTextStyles.heading2),
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Appliance details',
                        style: AppTextStyles.heading3,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Add the brand and product to identify your appliance. Other details are optional.',
                        style: AppTextStyles.body.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        key: _brandKey,
                        label: 'Brand (required)',
                        hint: 'e.g. Samsung',
                        controller: _brandController,
                        focusNode: _brandFocus,
                        enabled: !_isSaving,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _productFocus.requestFocus(),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter the appliance brand.'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        key: _productKey,
                        label: 'Product (required)',
                        hint: 'e.g. Washing machine',
                        controller: _productController,
                        focusNode: _productFocus,
                        enabled: !_isSaving,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter the type of product.'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _buildDropdown(
                        label: 'Category (optional)',
                        hint: 'Choose a category',
                        value: _selectedCategory,
                        items: AppConstants.applianceCategories,
                        onChanged: (value) =>
                            setState(() => _selectedCategory = value),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _buildDropdown(
                        label: 'Size (optional)',
                        hint: 'Choose a size',
                        value: _selectedSize,
                        items: AppConstants.applianceSizes,
                        onChanged: (value) =>
                            setState(() => _selectedSize = value),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const Text(
                        'Identification',
                        style: AppTextStyles.heading3,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'You can find these numbers on the appliance label.',
                        style: AppTextStyles.body.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: 'Model number (optional)',
                        hint: 'e.g. AR12TYHYCWKN',
                        controller: _modelController,
                        enabled: !_isSaving,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: 'Serial number (optional)',
                        hint: 'e.g. 0B7T3XBK500001',
                        controller: _serialController,
                        enabled: !_isSaving,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleSubmit(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_saveError != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: AppCard(
                            color: scheme.errorContainer,
                            child: Text(
                              _saveError!,
                              style: AppTextStyles.body.copyWith(
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      AppButton(
                        label: 'Add appliance',
                        loadingLabel: 'Adding appliance...',
                        icon: Icons.add_outlined,
                        onPressed: _handleSubmit,
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

  Widget _buildDropdown({
    required String label,
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: label,
          child: DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            isDense: false,
            itemHeight: null,
            menuMaxHeight: 360,
            style: AppTextStyles.body.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            hint: Text(hint, style: AppTextStyles.body),
            icon: const Icon(Icons.expand_more_outlined),
            items: items
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(item),
                    ),
                  ),
                )
                .toList(),
            onChanged: _isSaving ? null : onChanged,
          ),
        ),
      ],
    );
  }
}

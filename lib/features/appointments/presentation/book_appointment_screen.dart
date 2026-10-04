import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../profile/data/customer_repository.dart';
import '../../shared/models/customer.dart';
import '../data/appointments_repository.dart';

class BookAppointmentScreen extends ConsumerStatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  ConsumerState<BookAppointmentScreen> createState() =>
      _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends ConsumerState<BookAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleFieldKey = GlobalKey();
  final _dateFieldKey = GlobalKey<FormFieldState<DateTime>>();
  final _timeFieldKey = GlobalKey<FormFieldState<String>>();
  final _titleFocus = FocusNode();
  final _dateFocus = FocusNode();
  final _timeFocus = FocusNode();
  final _titleController = TextEditingController();
  final _applianceController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedTimeSlot;
  Customer? _customer;
  bool _isLoading = false;
  bool _isLoadingCustomer = true;
  bool _customerLoadFailed = false;
  String? _bookingError;

  bool get _hasRequiredAddress =>
      !_isLoadingCustomer &&
      !_customerLoadFailed &&
      (_customer?.address?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _loadCustomer();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _applianceController.dispose();
    _notesController.dispose();
    _titleFocus.dispose();
    _dateFocus.dispose();
    _timeFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCustomer() async {
    setState(() {
      _isLoadingCustomer = true;
      _customerLoadFailed = false;
      _customer = null;
    });
    try {
      final customer = await ref
          .read(customerRepositoryProvider)
          .getCurrentCustomer()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _customerLoadFailed = customer == null;
      });
    } catch (_) {
      if (mounted) setState(() => _customerLoadFailed = true);
    } finally {
      if (mounted) setState(() => _isLoadingCustomer = false);
    }
  }

  Future<void> _editAddress() async {
    await context.push('/profile/edit');
    if (mounted) await _loadCustomer();
  }

  Future<void> _pickDate(FormFieldState<DateTime> field) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final initialDate = _selectedDate != null && !_selectedDate!.isBefore(today)
        ? _selectedDate!
        : today.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      helpText: 'Choose your preferred date',
      initialDate: initialDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
    );
    if (!mounted || picked == null) return;
    field.didChange(picked);
    setState(() => _selectedDate = picked);
  }

  Future<void> _handleBook() async {
    if (_isLoading || !_hasRequiredAddress) return;
    if (!_formKey.currentState!.validate()) {
      _revealFirstInvalidField();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _bookingError = null;
    });
    try {
      await ref.read(appointmentsRepositoryProvider).bookAppointment({
        'title': _titleController.text.trim(),
        'appliance_name': _applianceController.text.trim(),
        'appointment_date': _selectedDate!.toIso8601String(),
        'time_slot': _selectedTimeSlot,
        'notes': _notesController.text.trim(),
        'status': 'Pending',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment booked. Status: pending.')),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/appointments');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _bookingError = error is StateError
            ? error.message.toString()
            : 'We couldn’t book your appointment. Please try again.';
      });
      if (error is AppointmentAddressRequiredException) {
        await _loadCustomer();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _revealFirstInvalidField() {
    final GlobalKey fieldKey;
    final FocusNode focusNode;
    if (_titleController.text.trim().isEmpty) {
      fieldKey = _titleFieldKey;
      focusNode = _titleFocus;
    } else if (_dateFieldKey.currentState?.hasError ?? false) {
      fieldKey = _dateFieldKey;
      focusNode = _dateFocus;
    } else {
      fieldKey = _timeFieldKey;
      focusNode = _timeFocus;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      focusNode.requestFocus();
      final fieldContext = fieldKey.currentContext;
      if (fieldContext != null) {
        Scrollable.ensureVisible(
          fieldContext,
          alignment: 0.15,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Book a repair')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Let’s get it working again.',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Tell us what needs fixing and choose a time that works for you.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'All fields are required unless marked optional.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _section(
                      number: '1',
                      title: 'Repair details',
                      description: 'A short description helps us prepare.',
                      children: [
                        AppTextField(
                          key: _titleFieldKey,
                          focusNode: _titleFocus,
                          label: 'What needs fixing?',
                          hint: 'e.g. Air conditioner isn’t cooling',
                          controller: _titleController,
                          enabled: !_isLoading,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Describe what needs fixing.'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppTextField(
                          label: 'Appliance / model (optional)',
                          hint: 'e.g. Samsung split-type AC',
                          controller: _applianceController,
                          enabled: !_isLoading,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _section(
                      number: '2',
                      title: 'Choose a schedule',
                      description: 'Select your preferred date and time.',
                      children: [
                        _dateField(),
                        const SizedBox(height: AppSpacing.lg),
                        _timeField(),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _section(
                      number: '3',
                      title: 'Your contact details',
                      description:
                          'A saved address is required to book your repair.',
                      children: [_customerDetails()],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _section(
                      number: '4',
                      title: 'Notes & review',
                      description: 'Check your details before booking.',
                      children: [
                        AppTextField(
                          label: 'Anything else? (optional)',
                          hint: 'Share symptoms or previous repairs…',
                          controller: _notesController,
                          maxLines: 3,
                          enabled: !_isLoading,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _titleController,
                          builder: (context, value, child) => _summaryRow(
                            Icons.build_outlined,
                            'Repair',
                            value.text.trim().isEmpty
                                ? 'Describe your repair above'
                                : value.text.trim(),
                          ),
                        ),
                        _summaryRow(
                          Icons.calendar_today_outlined,
                          'Preferred date',
                          _selectedDate == null
                              ? 'Choose a date above'
                              : DateFormat.yMMMd().format(_selectedDate!),
                        ),
                        _summaryRow(
                          Icons.schedule_outlined,
                          'Preferred time',
                          _selectedTimeSlot ?? 'Choose a time above',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Your appointment will be marked as pending. You can track its status in Appointments.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_bookingError != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                          ),
                          child: Text(
                            _bookingError!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AppButton(
                      label: 'Book appointment',
                      loadingLabel: 'Booking appointment…',
                      icon: Icons.check_circle_outline,
                      onPressed: _hasRequiredAddress ? _handleBook : null,
                      isLoading: _isLoading,
                      width: double.infinity,
                    ),
                    if (!_hasRequiredAddress) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _isLoadingCustomer
                              ? 'Checking your saved address before booking.'
                              : _customerLoadFailed
                              ? 'Reload your contact details above to continue.'
                              : 'Add your address above to continue.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section({
    required String number,
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  number,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }

  Widget _dateField() {
    return FormField<DateTime>(
      key: _dateFieldKey,
      validator: (value) {
        if (value == null) return 'Choose a preferred date.';
        if (value.isBefore(DateUtils.dateOnly(DateTime.now()))) {
          return 'Choose today or a later date.';
        }
        return null;
      },
      builder: (field) => Semantics(
        button: true,
        enabled: !_isLoading,
        child: InkWell(
          focusNode: _dateFocus,
          onTap: _isLoading ? null : () => _pickDate(field),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Preferred date',
              errorText: field.errorText,
              errorMaxLines: 3,
              enabled: !_isLoading,
              suffixIcon: const Icon(Icons.calendar_today_outlined),
            ),
            child: Text(
              _selectedDate == null
                  ? 'Choose a date'
                  : DateFormat.yMMMEd().format(_selectedDate!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeField() {
    return DropdownButtonFormField<String>(
      key: _timeFieldKey,
      focusNode: _timeFocus,
      initialValue: _selectedTimeSlot,
      validator: (value) => value == null ? 'Choose a preferred time.' : null,
      decoration: InputDecoration(
        labelText: 'Preferred time',
        errorMaxLines: 3,
        enabled: !_isLoading,
      ),
      hint: const Text('Select a time slot'),
      isExpanded: true,
      isDense: false,
      itemHeight: null,
      items: AppConstants.timeSlots
          .map((slot) => DropdownMenuItem(value: slot, child: Text(slot)))
          .toList(),
      onChanged: _isLoading
          ? null
          : (value) => setState(() => _selectedTimeSlot = value),
    );
  }

  Widget _customerDetails() {
    final theme = Theme.of(context);
    if (_isLoadingCustomer) {
      return Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (MediaQuery.disableAnimationsOf(context))
              Icon(
                Icons.hourglass_empty_outlined,
                color: theme.colorScheme.primary,
              )
            else
              const LinearProgressIndicator(
                semanticsLabel: 'Loading contact details',
              ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Loading your contact details…'),
          ],
        ),
      );
    }
    if (_customerLoadFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('We couldn’t load your contact details.'),
          TextButton.icon(
            onPressed: _isLoading ? null : _loadCustomer,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Try again'),
          ),
        ],
      );
    }
    final customer = _customer!;
    final address = customer.address?.trim() ?? '';
    final phone = customer.phoneNo?.trim() ?? '';
    final email = customer.email?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (customer.fullName.isNotEmpty)
          _summaryRow(Icons.person_outline, 'Name', customer.fullName),
        if (phone.isNotEmpty) _summaryRow(Icons.phone_outlined, 'Phone', phone),
        if (email.isNotEmpty) _summaryRow(Icons.email_outlined, 'Email', email),
        _summaryRow(
          Icons.location_on_outlined,
          'Saved address',
          address.isEmpty ? 'No address added yet' : address,
        ),
        if (address.isEmpty)
          Text(
            'Add your address before booking. Enter it yourself or use your phone location in your profile.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _editAddress,
          icon: Icon(
            address.isEmpty
                ? Icons.add_location_alt_outlined
                : Icons.edit_outlined,
          ),
          label: Text(address.isEmpty ? 'Add address' : 'Edit contact details'),
        ),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

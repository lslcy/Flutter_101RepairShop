import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_dates.dart';
import '../../../core/utils/appointment_reminder_time.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../profile/data/customer_repository.dart';
import '../../shared/models/appliance.dart';
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
  final _applianceFieldKey = GlobalKey();
  final _dateFieldKey = GlobalKey<FormFieldState<DateTime>>();
  final _timeFieldKey = GlobalKey<FormFieldState<String>>();
  final _reminderFieldKey = GlobalKey<FormFieldState<int>>();
  final _titleFocus = FocusNode();
  final _applianceFocus = FocusNode();
  final _dateFocus = FocusNode();
  final _timeFocus = FocusNode();
  final _reminderFocus = FocusNode();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedTimeSlot;
  int? _selectedReminderMinutes;
  bool _checkingReminderPermission = false;
  bool _reminderPermissionDenied = false;
  Customer? _customer;
  List<Appliance> _appliances = [];
  Appliance? _selectedAppliance;
  bool _isLoading = false;
  bool _isLoadingCustomer = true;
  bool _customerLoadFailed = false;
  bool _isLoadingAppliances = true;
  bool _appliancesLoadFailed = false;
  String? _bookingError;

  bool get _hasAppliances =>
      !_isLoadingAppliances && !_appliancesLoadFailed && _appliances.isNotEmpty;

  bool get _canBook =>
      _hasRequiredAddress && _hasAppliances && !_checkingReminderPermission;

  bool get _hasRequiredAddress =>
      !_isLoadingCustomer &&
      !_customerLoadFailed &&
      (_customer?.address?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _loadCustomer();
    _loadAppliances();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _titleFocus.dispose();
    _applianceFocus.dispose();
    _dateFocus.dispose();
    _timeFocus.dispose();
    _reminderFocus.dispose();
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

  /// Loads "My Appliances". When [preferNewFrom] is given, an appliance whose
  /// ID is not in it (i.e. one just added) is selected automatically.
  Future<void> _loadAppliances({Set<int>? preferNewFrom}) async {
    setState(() {
      _isLoadingAppliances = true;
      _appliancesLoadFailed = false;
    });
    try {
      final appliances = await ref
          .read(customerRepositoryProvider)
          .getAppliances()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final added = preferNewFrom == null
          ? null
          : appliances.where((a) => !preferNewFrom.contains(a.id)).firstOrNull;
      final previousId = _selectedAppliance?.id;
      setState(() {
        _appliances = appliances;
        _selectedAppliance =
            added ??
            appliances.where((a) => a.id == previousId).firstOrNull ??
            (appliances.length == 1 ? appliances.first : null);
      });
    } catch (_) {
      if (mounted) setState(() => _appliancesLoadFailed = true);
    } finally {
      if (mounted) setState(() => _isLoadingAppliances = false);
    }
  }

  Future<void> _addAppliance() async {
    final before = _appliances.map((a) => a.id).toSet();
    await context.push('/profile/appliances/add');
    if (mounted) await _loadAppliances(preferNewFrom: before);
  }

  Future<void> _pickDate(FormFieldState<DateTime> field) async {
    final today = AppDates.manilaToday();
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
    if (_isLoading || !_canBook) return;
    if (!_formKey.currentState!.validate() || _selectedAppliance == null) {
      _revealFirstInvalidField();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _bookingError = null;
    });
    try {
      final insertedId = await ref
          .read(appointmentsRepositoryProvider)
          .bookAppointment({
            'title': _titleController.text.trim(),
            // Filled from the chosen saved appliance (brand, product, model, S/N).
            'appliance_name': _selectedAppliance!.bookingLabel,
            'appointment_date': AppDates.toDateString(_selectedDate!),
            'time_slot': _selectedTimeSlot,
            'notes': _notesController.text.trim(),
            'reminder_minutes': _selectedReminderMinutes,
            'status': 'Pending',
          });
      if (!mounted) return;

      // Device delivery cannot turn an already saved booking into a failed one.
      var message = 'Appointment booked. Status: pending.';
      if (_selectedReminderMinutes != null) {
        final result = insertedId == null
            ? ReminderScheduleResult.failed
            : await ref
                  .read(notificationServiceProvider)
                  .scheduleAppointmentReminder(
                    appointmentId: insertedId,
                    title: _titleController.text.trim(),
                    appointmentDate: _selectedDate!,
                    timeSlot: _selectedTimeSlot,
                    reminderMinutes: _selectedReminderMinutes!,
                  );
        message = switch (result) {
          ReminderScheduleResult.scheduled =>
            'Appointment booked. Your reminder is set.',
          ReminderScheduleResult.tooLate => 'Appointment booked. The selected reminder time has already passed.',
          ReminderScheduleResult.unavailable => 'Appointment booked. Allow notifications in your phone settings to receive your reminder.',
          _ => 'Appointment booked. We could not set the device reminder. Reopen the app to retry.',
        };
      }
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
    if (_selectedAppliance == null) {
      fieldKey = _applianceFieldKey;
      focusNode = _applianceFocus;
    } else if (_titleController.text.trim().isEmpty) {
      fieldKey = _titleFieldKey;
      focusNode = _titleFocus;
    } else if (_dateFieldKey.currentState?.hasError ?? false) {
      fieldKey = _dateFieldKey;
      focusNode = _dateFocus;
    } else if (_reminderFieldKey.currentState?.hasError ?? false) {
      fieldKey = _reminderFieldKey;
      focusNode = _reminderFocus;
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
                      description: 'Pick an appliance from My Appliances and tell us what is wrong.',
                      children: [
                        _applianceField(),
                        const SizedBox(height: AppSpacing.md),
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
                        const SizedBox(height: AppSpacing.lg),
                        _reminderField(),
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
                        _summaryRow(
                          Icons.kitchen_outlined,
                          'Appliance',
                          _selectedAppliance?.bookingLabel ??
                              'Choose an appliance above',
                        ),
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
                        _summaryRow(
                          Icons.notifications_active_outlined,
                          'Reminder',
                          _selectedReminderMinutes == null
                              ? 'No reminder set'
                              : AppConstants.reminderOptions.entries
                                        .where(
                                          (e) =>
                                              e.value ==
                                              _selectedReminderMinutes,
                                        )
                                        .firstOrNull
                                        ?.key ??
                                    '$_selectedReminderMinutes min before',
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
                      onPressed: _canBook ? _handleBook : null,
                      isLoading: _isLoading,
                      width: double.infinity,
                    ),
                    if (!_canBook) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _isLoadingCustomer || _isLoadingAppliances
                              ? 'Loading your details before booking.'
                              : _appliancesLoadFailed
                              ? 'Reload your appliances above to continue.'
                              : _appliances.isEmpty
                              ? 'Add an appliance above to continue.'
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
        if (value.isBefore(AppDates.manilaToday())) {
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

  Widget _applianceField() {
    final theme = Theme.of(context);
    if (_isLoadingAppliances) {
      return Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!MediaQuery.disableAnimationsOf(context))
              const LinearProgressIndicator(
                semanticsLabel: 'Loading your appliances',
              ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Loading your appliances…'),
          ],
        ),
      );
    }
    if (_appliancesLoadFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('We couldn’t load your appliances.'),
          TextButton.icon(
            onPressed: _isLoading ? null : _loadAppliances,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Try again'),
          ),
        ],
      );
    }
    if (_appliances.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'You have no saved appliances yet. Add the appliance that needs repair to My Appliances first.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _addAppliance,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add an appliance'),
          ),
        ],
      );
    }

    final selected = _selectedAppliance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          key: _applianceFieldKey,
          focusNode: _applianceFocus,
          initialValue: selected?.id,
          validator: (value) =>
              value == null ? 'Choose the appliance that needs repair.' : null,
          decoration: InputDecoration(
            labelText: 'Appliance (from My Appliances)',
            errorMaxLines: 3,
            enabled: !_isLoading,
            prefixIcon: const Icon(Icons.kitchen_outlined),
          ),
          hint: const Text('Select an appliance'),
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          selectedItemBuilder: (context) => _appliances
              .map(
                (a) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(a.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          items: _appliances.map((a) {
            final subtitle = [
              a.category?.trim() ?? '',
              if (a.modelNo?.trim().isNotEmpty ?? false)
                'Model ${a.modelNo!.trim()}',
            ].where((part) => part.isNotEmpty).join(' · ');
            return DropdownMenuItem(
              value: a.id,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(a.label),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
          onChanged: _isLoading
              ? null
              : (id) => setState(
                  () => _selectedAppliance = _appliances
                      .where((a) => a.id == id)
                      .firstOrNull,
                ),
        ),
        if (selected != null) ...[
          const SizedBox(height: AppSpacing.md),
          _applianceDetails(selected),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _isLoading ? null : _addAppliance,
            icon: const Icon(Icons.add),
            label: const Text('Not listed? Add an appliance'),
          ),
        ),
      ],
    );
  }

  /// Read-only details filled in from the chosen saved appliance.
  Widget _applianceDetails(Appliance appliance) {
    final theme = Theme.of(context);
    String? clean(String? value) =>
        (value?.trim().isNotEmpty ?? false) ? value!.trim() : null;
    final brand = clean(appliance.brand);
    final product = clean(appliance.product);
    final category = clean(appliance.category);
    final size = clean(appliance.applianceSize);
    final model = clean(appliance.modelNo);
    final serial = clean(appliance.serialNo);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (brand != null) _summaryRow(Icons.sell_outlined, 'Brand', brand),
          if (product != null)
            _summaryRow(Icons.devices_other_outlined, 'Product', product),
          if (category != null)
            _summaryRow(Icons.category_outlined, 'Category', category),
          if (size != null)
            _summaryRow(Icons.straighten_outlined, 'Size', size),
          if (model != null)
            _summaryRow(Icons.tag_outlined, 'Model no.', model),
          if (serial != null)
            _summaryRow(Icons.qr_code_2_outlined, 'Serial no.', serial),
          _summaryRow(
            Icons.verified_outlined,
            'Warranty',
            appliance.warrantyLabel,
          ),
        ],
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

  Future<void> _selectReminder(int? minutes) async {
    setState(() {
      _selectedReminderMinutes = minutes;
      _reminderPermissionDenied = false;
      _checkingReminderPermission = minutes != null;
    });
    if (minutes == null) return;
    final allowed = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    if (!mounted) return;
    setState(() {
      _checkingReminderPermission = false;
      _reminderPermissionDenied = !allowed;
    });
  }

  Widget _reminderField() {
    return DropdownButtonFormField<int>(
      key: _reminderFieldKey,
      focusNode: _reminderFocus,
      initialValue: _selectedReminderMinutes,
      validator: (value) {
        if (value == null ||
            _selectedDate == null ||
            _selectedTimeSlot == null) {
          return null;
        }
        final deadline = AppointmentReminderTime.reminderTime(
          _selectedDate!,
          _selectedTimeSlot,
          value,
        );
        return deadline == null || !deadline.isAfter(DateTime.now())
            ? 'Choose a shorter reminder or a later appointment time.'
            : null;
      },
      decoration: InputDecoration(
        labelText: 'Remind me (optional)',
        enabled: !_isLoading && !_checkingReminderPermission,
        prefixIcon: const Icon(Icons.notifications_active_outlined),
        helperText: _checkingReminderPermission
            ? 'Checking notification permission...'
            : _reminderPermissionDenied
            ? 'Your choice will be saved. Allow notifications in phone settings to receive reminders.'
            : 'Choose how early to be reminded. Times use Philippine time.',
        helperMaxLines: 4,
        errorMaxLines: 3,
      ),
      hint: const Text('No reminder'),
      isExpanded: true,
      isDense: false,
      itemHeight: null,
      items: [
        const DropdownMenuItem<int>(value: null, child: Text('No reminder')),
        ...AppConstants.reminderOptions.entries.map(
          (entry) =>
              DropdownMenuItem(value: entry.value, child: Text(entry.key)),
        ),
      ],
      onChanged: _isLoading || _checkingReminderPermission
          ? null
          : _selectReminder,
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

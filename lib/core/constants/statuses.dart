// Status vocabularies shared with the Laravel web admin.
//
// Each `normalize` maps stored values (including legacy spellings) to the
// canonical label. Unknown values are returned trimmed so they still display
// instead of crashing or being silently hidden.

/// `service_reports.status`
class RepairStatus {
  RepairStatus._();

  static const pending = 'Pending';
  static const inProgress = 'In Progress';
  static const waitingForParts = 'Waiting for Parts';
  static const underRepair = 'Under Repair';
  static const completed = 'Completed';
  static const cancelled = 'Cancelled';

  static const values = [
    pending,
    inProgress,
    waitingForParts,
    underRepair,
    completed,
    cancelled,
  ];

  /// Statuses treated as "in progress" for filters and dashboards.
  static const inProgressGroup = {inProgress, waitingForParts, underRepair};

  static const _aliases = {
    'pending': pending,
    'in progress': inProgress,
    'in_progress': inProgress,
    'in-progress': inProgress,
    'ongoing': inProgress,
    'diagnosing': inProgress,
    'waiting for parts': waitingForParts,
    'waiting_for_parts': waitingForParts,
    'waiting-for-parts': waitingForParts,
    'under repair': underRepair,
    'under_repair': underRepair,
    'under-repair': underRepair,
    'completed': completed,
    'complete': completed,
    'cancelled': cancelled,
    'canceled': cancelled,
  };

  /// Canonical label. A missing status is shown as [pending].
  static String normalize(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return pending;
    return _aliases[value.toLowerCase()] ?? value;
  }

  static bool isKnown(String? raw) => values.contains(normalize(raw));

  static bool isInProgress(String? raw) =>
      inProgressGroup.contains(normalize(raw));

  /// Finished work that should no longer appear as "active".
  static bool isClosed(String? raw) {
    final status = normalize(raw);
    return status == completed ||
        status == cancelled ||
        const {'released', 'closed'}.contains(status.toLowerCase());
  }
}

/// `transactions.payment_status`
class PaymentStatus {
  PaymentStatus._();

  static const paid = 'Paid';
  static const unpaid = 'Unpaid';
  static const partial = 'Partial';

  static const values = [paid, unpaid, partial];

  /// Canonical label. Legacy `Pending` and missing values display as Unpaid.
  static String normalize(String? raw) {
    final value = raw?.trim() ?? '';
    switch (value.toLowerCase()) {
      case 'paid':
        return paid;
      case 'partial':
      case 'partially paid':
      case 'partial payment':
        return partial;
      case '':
      case 'unpaid':
      case 'pending':
        return unpaid;
      default:
        return value;
    }
  }

  static bool isPaid(String? raw) => normalize(raw) == paid;
}

/// `appointments.status`
class AppointmentStatus {
  AppointmentStatus._();

  static const pending = 'Pending';
  static const confirmed = 'Confirmed';
  static const completed = 'Completed';
  static const cancelled = 'Cancelled';

  static const values = [pending, confirmed, completed, cancelled];

  static String normalize(String? raw) {
    final value = raw?.trim() ?? '';
    switch (value.toLowerCase()) {
      case '':
      case 'pending':
        return pending;
      case 'confirmed':
        return confirmed;
      case 'completed':
      case 'complete':
        return completed;
      case 'cancelled':
      case 'canceled':
        return cancelled;
      default:
        return value;
    }
  }

  /// Customers may cancel only before staff complete or cancel the visit.
  static bool canCancel(String? raw) {
    final status = normalize(raw);
    return status == pending || status == confirmed;
  }

  static bool isClosed(String? raw) {
    final status = normalize(raw);
    return status == completed ||
        status == cancelled ||
        const {'released', 'closed'}.contains(status.toLowerCase());
  }
}

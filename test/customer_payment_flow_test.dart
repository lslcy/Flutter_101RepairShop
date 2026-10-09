import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/features/payments/data/payment_submission_repository.dart';
import 'package:flutter_101repairshop/features/payments/presentation/customer_payment_screen.dart';
import 'package:flutter_101repairshop/features/shared/models/payment_submission.dart';
import 'package:flutter_101repairshop/features/shared/models/transaction.dart'
    as models;

const _qrUrl = 'https://example.com/shop-gcash-qr.png';

PaymentSubmission _submission(String status, {String? note}) =>
    PaymentSubmission(
      id: 'submission-1',
      transactionId: 42,
      method: status == 'pay_at_shop' ? 'shop' : 'gcash',
      status: status,
      amount: 750,
      receiptPath: status == 'pay_at_shop' ? null : 'customer/42/receipt.png',
      reviewNote: note,
    );

class _FakePayments extends PaymentSubmissionRepository {
  _FakePayments(SupabaseClient client) : super(supabase: client);

  PaymentSubmission? current;
  models.Transaction? freshTransaction;
  bool missingTransaction = false;
  int transactionReads = 0;
  Object? loadError;
  Object? gcashError;
  Object? submitError;
  Object? shopError;
  Completer<PaymentSubmission>? pendingSubmission;
  Completer<PaymentSubmission>? pendingShop;
  final gcashReceipts = <ReceiptImage>[];
  final submittedTransactionIds = <int>[];
  int latestCalls = 0;
  int gcashDetailsCalls = 0;
  int shopCalls = 0;

  @override
  Future<models.Transaction?> getTransaction(int transactionId) async {
    transactionReads++;
    return missingTransaction ? null : freshTransaction;
  }

  @override
  Future<PaymentSubmission?> latestSubmission(int transactionId) async {
    latestCalls++;
    if (loadError != null) throw loadError!;
    return current;
  }

  @override
  Future<GcashPaymentDetails> getGcashDetails() async {
    gcashDetailsCalls++;
    if (gcashError != null) throw gcashError!;
    return const GcashPaymentDetails(
      qrImageUrl: _qrUrl,
      recipient: '101 RepairShop',
    );
  }

  @override
  Future<PaymentSubmission> submitGcash(
    int transactionId,
    ReceiptImage receipt,
  ) async {
    submittedTransactionIds.add(transactionId);
    gcashReceipts.add(receipt);
    if (submitError != null) throw submitError!;
    final result =
        await (pendingSubmission?.future ??
            Future.value(_submission('pending')));
    current = result;
    return result;
  }

  @override
  Future<PaymentSubmission> choosePayAtShop(int transactionId) async {
    shopCalls++;
    submittedTransactionIds.add(transactionId);
    if (shopError != null) throw shopError!;
    final result =
        await (pendingShop?.future ?? Future.value(_submission('pay_at_shop')));
    current = result;
    return result;
  }
}

class _FakeReceiptPicker extends ReceiptPicker {
  ReceiptImage? receipt;
  Object? error;
  int calls = 0;

  @override
  Future<ReceiptImage?> pick() async {
    calls++;
    if (error != null) throw error!;
    return receipt;
  }
}

void main() {
  late SupabaseClient client;
  late _FakePayments repository;
  late _FakeReceiptPicker picker;
  late ReceiptImage receipt;
  late ui.Image image;

  setUp(() async {
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repository = _FakePayments(client);
    picker = _FakeReceiptPicker();
    receipt = ReceiptImage(
      bytes: Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR42mNgAAAAAgABSK+kcQAAAABJRU5ErkJggg==',
        ),
      ),
      requestId: 'e3cbd704-1e2c-4c03-a482-fb182391f558',
    );
    image = await createTestImage(width: 16, height: 16);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    for (final key in <Object>[
      const NetworkImage(_qrUrl),
      MemoryImage(receipt.bytes),
    ]) {
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: image.clone())),
        ),
      );
    }
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    image.dispose();
    await client.dispose();
  });

  Future<models.Transaction> pumpPayment(
    WidgetTester tester, {
    bool dark = false,
    String status = 'Unpaid',
    double? total = 750,
    double? paid,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final transaction = models.Transaction(
      id: 42,
      customerId: 'customer-1',
      paymentStatus: status,
      totalAmount: total,
      partialPaymentAmount: paid,
    );
    repository.freshTransaction ??= transaction;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentSubmissionRepositoryProvider.overrideWithValue(repository),
          receiptPickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: CustomerPaymentScreen(transaction: transaction),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return transaction;
  }

  Finder appButton(String label) => find.byWidgetPredicate(
    (widget) => widget is AppButton && widget.label == label,
  );

  Future<void> tapVisible(
    WidgetTester tester,
    Finder target, {
    bool settle = true,
  }) async {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> openGcash(WidgetTester tester) async {
    await tapVisible(tester, find.text('GCash'));
    expect(find.text('Pay with GCash'), findsOneWidget);
    final qr = find.byWidgetPredicate(
      (widget) => widget is Image && widget.image == const NetworkImage(_qrUrl),
    );
    expect(qr, findsOneWidget);
    expect(
      tester.widget<Image>(qr).semanticLabel,
      'GCash payment QR code for 101 RepairShop',
    );
    expect(tester.widget<AppButton>(appButton('Next')).onPressed, isNotNull);
    await tapVisible(tester, appButton('Next'));
    expect(find.text('Upload your receipt'), findsOneWidget);
  }

  Future<void> chooseReceipt(WidgetTester tester) async {
    picker.receipt = receipt;
    await tapVisible(tester, find.text('Choose receipt screenshot'));
    expect(find.text('Change receipt'), findsOneWidget);
    expect(
      tester.widget<AppButton>(appButton('Confirm payment')).onPressed,
      isNotNull,
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'GCash receipt becomes pending for admin review at 320px/200% in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final transaction = await pumpPayment(
          tester,
          dark: dark,
          status: 'Partial',
          total: 1250,
          paid: 500,
        );
        await openGcash(tester);
        expect(
          tester.widget<AppButton>(appButton('Confirm payment')).onPressed,
          isNull,
        );
        await chooseReceipt(tester);
        await tapVisible(tester, appButton('Confirm payment'));
        expect(find.text('Pending'), findsOneWidget);
        expect(
          find.text(
            'Your GCash receipt was submitted. The admin will verify it before marking this payment as paid.',
          ),
          findsOneWidget,
        );
        expect(find.text('Paid'), findsNothing);
        expect(appButton('Confirm payment'), findsNothing);
        expect(repository.gcashReceipts, [receipt]);
        expect(repository.submittedTransactionIds, [42]);
        expect(transaction.isPaid, isFalse);
        expect(transaction.remainingBalance, 750);
        final scope = ProviderScope.containerOf(
          tester.element(find.byType(CustomerPaymentScreen)),
        );
        expect(scope.read(paymentUpdatesProvider), greaterThanOrEqualTo(1));
        await tester.ensureVisible(appButton('Done'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(appButton('Done')).height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('QR loading and failure prevent advancing to receipt upload', (
    tester,
  ) async {
    final qr = Completer<ImageInfo>();
    PaintingBinding.instance.imageCache.evict(const NetworkImage(_qrUrl));
    PaintingBinding.instance.imageCache.putIfAbsent(
      const NetworkImage(_qrUrl),
      () => OneFrameImageStreamCompleter(qr.future),
    );
    await pumpPayment(tester);
    await tapVisible(tester, find.text('GCash'));
    expect(find.text('Pay with GCash'), findsOneWidget);
    expect(tester.widget<AppButton>(appButton('Next')).onPressed, isNull);
    expect(find.text('Upload your receipt'), findsNothing);
    qr.completeError(StateError('Test QR unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('We could not load the QR code.'), findsOneWidget);
    expect(tester.widget<AppButton>(appButton('Next')).onPressed, isNull);
    expect(find.text('Upload your receipt'), findsNothing);
    await tapVisible(tester, find.text('Change payment method'));
    expect(find.text('GCash'), findsOneWidget);
    expect(find.text('Pay at the shop'), findsOneWidget);
    expect(repository.gcashReceipts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreadable receipt cannot be confirmed and can be replaced', (
    tester,
  ) async {
    final decodingReceipt = Completer<ImageInfo>();
    PaintingBinding.instance.imageCache.evict(MemoryImage(receipt.bytes));
    PaintingBinding.instance.imageCache.putIfAbsent(
      MemoryImage(receipt.bytes),
      () => OneFrameImageStreamCompleter(decodingReceipt.future),
    );
    await pumpPayment(tester);
    await openGcash(tester);
    picker.receipt = receipt;
    await tapVisible(tester, find.text('Choose receipt screenshot'));
    expect(
      tester.widget<AppButton>(appButton('Confirm payment')).onPressed,
      isNull,
    );
    expect(repository.gcashReceipts, isEmpty);
    decodingReceipt.completeError(StateError('Test receipt unreadable'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This receipt image could not be previewed. Choose another image.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AppButton>(appButton('Confirm payment')).onPressed,
      isNull,
    );
    expect(repository.gcashReceipts, isEmpty);
    final replacement = ReceiptImage(bytes: receipt.bytes);
    PaintingBinding.instance.imageCache.putIfAbsent(
      MemoryImage(replacement.bytes),
      () => OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: image.clone())),
      ),
    );
    picker.receipt = replacement;
    await tapVisible(tester, find.text('Change receipt'));
    expect(
      tester.widget<AppButton>(appButton('Confirm payment')).onPressed,
      isNotNull,
    );
    await tapVisible(tester, appButton('Confirm payment'));
    expect(repository.gcashReceipts, [replacement]);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed status read blocks new choices until a successful retry',
    (tester) async {
      repository.loadError = const PaymentFlowException(
        'We could not load your payment status.',
      );
      await pumpPayment(tester);
      expect(repository.latestCalls, 1);
      expect(
        find.text('We could not load your payment status.'),
        findsOneWidget,
      );
      expect(find.text('GCash'), findsNothing);
      expect(find.text('Pay at the shop'), findsNothing);
      expect(repository.shopCalls, 0);
      expect(repository.gcashReceipts, isEmpty);
      repository.loadError = null;
      repository.current = _submission('pending');
      await tapVisible(tester, find.text('Refresh payment status'));
      expect(repository.latestCalls, 2);
      expect(find.text('We could not load your payment status.'), findsNothing);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('GCash'), findsNothing);
      expect(find.text('Pay at the shop'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canceling receipt selection cannot submit payment', (
    tester,
  ) async {
    await pumpPayment(tester);
    await openGcash(tester);
    await tapVisible(tester, find.text('Choose receipt screenshot'));
    expect(picker.calls, 1);
    expect(
      tester.widget<AppButton>(appButton('Confirm payment')).onPressed,
      isNull,
    );
    expect(repository.gcashReceipts, isEmpty);
    expect(find.text('Pending'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'receipt picker errors are announced and leave confirmation disabled',
    (tester) async {
      picker.error = const PaymentFlowException(
        'Choose a receipt image smaller than 5 MB.',
      );
      await pumpPayment(tester);
      await openGcash(tester);
      await tapVisible(tester, find.text('Choose receipt screenshot'));
      final error = find.text('Choose a receipt image smaller than 5 MB.');
      expect(error.hitTestable(), findsOneWidget);
      expect(
        tester.widget<AppButton>(appButton('Confirm payment')).onPressed,
        isNull,
      );
      expect(repository.gcashReceipts, isEmpty);
      final semantics = tester.widgetList<Semantics>(
        find.ancestor(of: error, matching: find.byType(Semantics)),
      );
      expect(
        semantics.any((widget) => widget.properties.liveRegion == true),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'busy confirmation prevents a second submit or receipt replacement',
    (tester) async {
      repository.pendingSubmission = Completer<PaymentSubmission>();
      await pumpPayment(tester);
      await openGcash(tester);
      await chooseReceipt(tester);
      await tapVisible(tester, appButton('Confirm payment'), settle: false);
      expect(repository.gcashReceipts, [receipt]);
      expect(find.text('Submitting receipt...'), findsOneWidget);
      final confirm = tester.widget<AppButton>(appButton('Confirm payment'));
      expect(confirm.isLoading, isTrue);
      final upload = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Change receipt'),
      );
      expect(upload.onPressed, isNull);
      final back = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Back to QR code'),
      );
      expect(back.onPressed, isNull);
      final pop = tester.widget<PopScope>(find.byType(PopScope).first);
      expect(pop.canPop, isFalse);
      await tester.tap(appButton('Confirm payment'));
      await tester.pump();
      expect(repository.gcashReceipts.length, 1);
      repository.pendingSubmission!.complete(_submission('pending'));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Paid'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed confirmation retains the selected receipt for a retry', (
    tester,
  ) async {
    repository.submitError = const PaymentFlowException(
      'The receipt could not be submitted. Try again.',
    );
    await pumpPayment(tester, dark: true);
    await openGcash(tester);
    await chooseReceipt(tester);
    await tapVisible(tester, appButton('Confirm payment'));
    expect(
      find.text('The receipt could not be submitted. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Change receipt'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
    expect(repository.gcashReceipts.single.requestId, receipt.requestId);
    repository.submitError = null;
    await tapVisible(tester, appButton('Confirm payment'));
    expect(repository.gcashReceipts.length, 2);
    expect(repository.gcashReceipts[0], same(repository.gcashReceipts[1]));
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pay at the shop records preference and keeps the balance unpaid',
    (tester) async {
      final transaction = await pumpPayment(tester);
      await tapVisible(tester, find.text('Pay at the shop'));
      expect(repository.shopCalls, 1);
      expect(repository.gcashReceipts, isEmpty);
      expect(picker.calls, 0);
      expect(find.text('Pay at the shop selected'), findsOneWidget);
      expect(
        find.text(
          'Your balance is still unpaid. The shop will confirm payment when you pay in person.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pending'), findsNothing);
      expect(find.text('Paid'), findsNothing);
      expect(transaction.isPaid, isFalse);
      expect(transaction.remainingBalance, 750);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('GCash setup error leaves pay-at-shop available', (tester) async {
    repository.gcashError = const PaymentFlowException(
      'GCash is not available yet. You can choose Pay at the shop.',
    );
    await pumpPayment(tester);
    await tapVisible(tester, find.text('GCash'));
    expect(
      find.text('GCash is not available yet. You can choose Pay at the shop.'),
      findsOneWidget,
    );
    expect(appButton('Next'), findsNothing);
    await tapVisible(tester, find.text('Pay at the shop'));
    expect(repository.shopCalls, 1);
    expect(find.text('Pay at the shop selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending receipt reload offers no new payment choices', (
    tester,
  ) async {
    repository.current = _submission('pending');
    await pumpPayment(tester, dark: true);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('GCash'), findsNothing);
    expect(find.text('Pay at the shop'), findsNothing);
    expect(appButton('Confirm payment'), findsNothing);
    expect(repository.gcashReceipts, isEmpty);
    expect(repository.shopCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refresh shows manual approval with zero balance on an older unpaid snapshot',
    (tester) async {
      repository.current = _submission('pending');
      final transaction = await pumpPayment(tester);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('₱750.00'), findsOneWidget);
      repository.current = _submission('approved');
      repository.freshTransaction = models.Transaction(
        id: 42,
        customerId: 'customer-1',
        paymentStatus: 'Paid',
        paymentMethod: 'GCash',
        totalAmount: 750,
      );
      await tapVisible(tester, find.text('Refresh payment status'));
      expect(repository.latestCalls, 2);
      expect(find.text('Pending'), findsNothing);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('₱0.00'), findsOneWidget);
      expect(find.text('₱750.00'), findsNothing);
      expect(find.text('GCash'), findsNothing);
      expect(find.text('Pay at the shop'), findsNothing);
      expect(transaction.isPaid, isFalse);
      expect(repository.gcashReceipts, isEmpty);
      expect(repository.shopCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final amount in <double?>[null, 0]) {
    testWidgets(
      'no payment can be initiated without a positive bill: $amount',
      (tester) async {
        await pumpPayment(tester, total: amount);
        expect(find.text('Balance not available'), findsOneWidget);
        expect(
          find.text(
            'The shop needs to set your balance before you can choose a payment method.',
          ),
          findsOneWidget,
        );
        expect(find.text('GCash'), findsNothing);
        expect(find.text('Pay at the shop'), findsNothing);
        expect(repository.gcashReceipts, isEmpty);
        expect(repository.shopCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'refresh sees payment staff recorded at the shop and removes customer choices',
    (tester) async {
      repository.current = _submission('pay_at_shop');
      await pumpPayment(tester);
      expect(find.text('Pay at the shop selected'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      repository.freshTransaction = models.Transaction(
        id: 42,
        customerId: 'customer-1',
        paymentStatus: 'Paid',
        paymentMethod: 'Cash',
        totalAmount: 750,
      );
      // The explicit refresh remains visible for saved in-person preferences.
      await tapVisible(tester, find.text('Refresh payment status'));
      expect(repository.transactionReads, 2);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('₱0.00'), findsOneWidget);
      expect(find.text('GCash'), findsNothing);
      expect(find.text('Pay at the shop'), findsNothing);
      expect(repository.shopCalls, 0);
      expect(repository.gcashReceipts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh updates the balance before a replacement GCash receipt',
    (tester) async {
      repository.current = _submission('pending');
      await pumpPayment(tester);
      repository.current = _submission(
        'rejected',
        note: 'Please send a new receipt.',
      );
      repository.freshTransaction = models.Transaction(
        id: 42,
        customerId: 'customer-1',
        paymentStatus: 'Partial',
        totalAmount: 2000,
        partialPaymentAmount: 500,
      );
      await tapVisible(tester, find.text('Refresh payment status'));
      expect(find.text('₱1,500.00'), findsOneWidget);
      await tapVisible(tester, find.text('GCash'));
      expect(find.text('Send ₱1,500.00 to 101 RepairShop.'), findsOneWidget);
      expect(repository.transactionReads, 2);
      expect(repository.gcashReceipts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing transaction blocks choices and allows a safe retry', (
    tester,
  ) async {
    repository.missingTransaction = true;
    await pumpPayment(tester);
    expect(find.text('GCash'), findsNothing);
    expect(find.text('Pay at the shop'), findsNothing);
    expect(repository.latestCalls, 1);
    expect(repository.gcashReceipts, isEmpty);
    repository.missingTransaction = false;
    await tapVisible(tester, find.text('Refresh payment status'));
    expect(repository.transactionReads, 2);
    expect(repository.latestCalls, 2);
    expect(find.text('GCash'), findsOneWidget);
    expect(find.text('Pay at the shop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'historical approved receipt does not hide a new unpaid balance',
    (tester) async {
      repository.current = _submission('approved');
      await pumpPayment(tester, total: 1250);
      expect(find.text('Paid'), findsNothing);
      expect(find.text('₱0.00'), findsNothing);
      expect(find.text('₱1,250.00'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Pay at the shop'), findsOneWidget);
      await tapVisible(tester, find.text('GCash'));
      expect(find.text('Send ₱1,250.00 to 101 RepairShop.'), findsOneWidget);
      expect(repository.gcashReceipts, isEmpty);
      expect(repository.shopCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('paid payment hides both customer choices', (tester) async {
    await pumpPayment(tester, status: 'Paid');
    expect(find.text('Paid'), findsOneWidget);
    expect(
      find.text('This payment has been confirmed by the shop.'),
      findsOneWidget,
    );
    expect(find.text('GCash'), findsNothing);
    expect(find.text('Pay at the shop'), findsNothing);
    expect(appButton('Next'), findsNothing);
    expect(repository.gcashReceipts, isEmpty);
    expect(repository.shopCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rejected receipt shows the admin note and allows a replacement',
    (tester) async {
      repository.current = _submission(
        'rejected',
        note: 'The reference number is unreadable.',
      );
      await pumpPayment(tester);
      expect(find.text('Receipt needs attention'), findsOneWidget);
      expect(find.text('The reference number is unreadable.'), findsOneWidget);
      await openGcash(tester);
      await chooseReceipt(tester);
      await tapVisible(tester, appButton('Confirm payment'));
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Receipt needs attention'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_101repairshop/features/payments/data/payment_submission_repository.dart';
import 'package:flutter_101repairshop/features/shared/models/payment_submission.dart';
import 'package:flutter_101repairshop/features/shared/models/transaction.dart'
    as models;

const _authId = '11111111-1111-4111-8111-111111111111';
const _requestId = '22222222-2222-4222-8222-222222222222';
final _png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]);

void main() {
  test('receipt type is checked from bytes, independent of the filename', () {
    expect(ReceiptImage(bytes: _png).contentType, 'image/png');
    expect(
      ReceiptImage(bytes: Uint8List.fromList([255, 216, 255, 0])).extension,
      'jpg',
    );
    expect(
      () => ReceiptImage(
        bytes: Uint8List.fromList(utf8.encode('<script>bad</script>')),
      ),
      throwsA(isA<PaymentFlowException>()),
    );
    expect(
      () => ReceiptImage(bytes: Uint8List(ReceiptImage.maxBytes + 1)),
      throwsA(isA<PaymentFlowException>()),
    );
    expect(
      () => ReceiptImage(bytes: Uint8List(0)),
      throwsA(isA<PaymentFlowException>()),
    );
  });

  test('GCash settings must identify a real HTTPS image and recipient', () {
    for (final settings in [
      {
        'gcash_qr_image_url': 'http://shop.test/qr.png',
        'gcash_recipient_name': 'Shop',
      },
      {
        'gcash_qr_image_url': 'https://user:password@shop.test/qr.png',
        'gcash_recipient_name': 'Shop',
      },
      {
        'gcash_qr_image_url': 'https://shop.test/qr.png',
        'gcash_recipient_name': ' ',
      },
      <String, String>{},
    ]) {
      expect(
        () => GcashPaymentDetails.fromJson(settings),
        throwsA(isA<PaymentFlowException>()),
      );
    }
  });

  test('review status never erases a partial financial balance', () {
    final pending = PaymentSubmission(
      id: _requestId,
      transactionId: 7,
      method: 'gcash',
      status: 'pending',
      amount: 600,
    );
    final transaction = models.Transaction(
      id: 7,
      customerId: 'customer-1',
      totalAmount: 1000,
      partialPaymentAmount: 400,
      paymentStatus: 'Partial',
    ).withCustomerPayment(pending);
    expect(transaction.status, 'Pending');
    expect(transaction.isPaid, isFalse);
    expect(transaction.isPartial, isTrue);
    expect(transaction.amountPaid, 400);
    expect(transaction.remainingBalance, 600);
    expect(transaction.displayedPaymentMethod, 'GCash');
    expect(
      models.Transaction(
        id: 7,
        customerId: 'c',
        totalAmount: 1000,
        paymentStatus: 'Paid',
        customerPayment: pending,
      ).status,
      'Paid',
    );
  });

  group('private receipt upload and submission API', () {
    late _PaymentServer server;
    late SupabaseClient client;
    late PaymentSubmissionRepository repository;
    setUp(() async {
      server = _PaymentServer();
      await server.start();
      client = SupabaseClient(
        server.url,
        'local-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.signInWithPassword(
        email: 'test@example.com',
        password: 'Password1!',
      );
      repository = PaymentSubmissionRepository(supabase: client);
    });
    tearDown(() async {
      await client.dispose();
      await server.close();
    });

    test(
      'uploads an unchanged screenshot privately before requesting review',
      () async {
        final receipt = ReceiptImage(bytes: _png, requestId: _requestId);
        final result = await repository.submitGcash(7, receipt);
        expect(result.isPending, isTrue);
        expect(result.amount, 600);
        expect(
          server.uploads.single.$1,
          '/storage/v1/object/payment-receipts/$_authId/7/$_requestId.png',
        );
        expect(server.uploads.single.$2, orderedEquals(_png));
        expect(server.uploadTypes.single, 'image/png');
        expect(server.upserts.single, 'false');
        expect(server.rpcBodies.single, {
          'p_transaction_id': 7,
          'p_method': 'gcash',
          'p_receipt_path': '$_authId/7/$_requestId.png',
          'p_request_id': _requestId,
        });
        expect(server.financialWrites, isEmpty);
      },
    );

    test(
      'retry after lost RPC response reuses the same immutable receipt and ID',
      () async {
        final receipt = ReceiptImage(bytes: _png, requestId: _requestId);
        server.failRpcOnce = true;
        await expectLater(
          repository.submitGcash(7, receipt),
          throwsA(isA<PostgrestException>()),
        );
        final result = await repository.submitGcash(7, receipt);
        expect(result.isPending, isTrue);
        expect(server.uploads, hasLength(2));
        expect(server.uploads[0].$1, server.uploads[1].$1);
        expect(server.rpcBodies, hasLength(2));
        expect(server.rpcBodies.first, server.rpcBodies.last);
      },
    );

    test(
      'known 400 duplicate upload also allows the same receipt retry',
      () async {
        final receipt = ReceiptImage(bytes: _png, requestId: _requestId);
        server.failRpcOnce = true;
        await expectLater(
          repository.submitGcash(7, receipt),
          throwsA(isA<PostgrestException>()),
        );
        server.duplicateStatus = 400;
        expect((await repository.submitGcash(7, receipt)).isPending, isTrue);
        expect(server.rpcBodies.first, server.rpcBodies.last);
      },
    );

    test(
      'other 400 upload errors do not create a pending submission',
      () async {
        server.uploadFailureStatus = 400;
        await expectLater(
          repository.submitGcash(7, ReceiptImage(bytes: _png)),
          throwsA(isA<StorageException>()),
        );
        expect(server.rpcBodies, isEmpty);
      },
    );

    test('slow payment API releases the caller for a safe retry', () async {
      server.delayRpc = const Duration(milliseconds: 100);
      final quickRepository = PaymentSubmissionRepository(
        supabase: client,
        requestTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        quickRepository.choosePayAtShop(7),
        throwsA(isA<TimeoutException>()),
      );
      expect(server.financialWrites, isEmpty);
    });

    test('transaction refresh reads staff status and amount without client updates', () async {
      final transaction = await repository.getTransaction(7);
      expect(transaction!.isPaid, isTrue);
      expect(transaction.remainingBalance, 0);
      expect(server.financialWrites, isEmpty);
    });

    test('upload denial never creates a pending payment', () async {
      server.rejectUpload = true;
      await expectLater(
        repository.submitGcash(7, ReceiptImage(bytes: _png)),
        throwsA(isA<StorageException>()),
      );
      expect(server.rpcBodies, isEmpty);
      expect(server.financialWrites, isEmpty);
    });

    test(
      'Pay at the shop stores a preference without a receipt or paid update',
      () async {
        final result = await repository.choosePayAtShop(7);
        expect(result.isPayAtShop, isTrue);
        expect(server.uploads, isEmpty);
        expect(server.rpcBodies.single['p_method'], 'shop');
        expect(server.rpcBodies.single['p_receipt_path'], isNull);
        expect(server.financialWrites, isEmpty);
      },
    );

    test(
      'no configured QR never invents payment destination details',
      () async {
        server.hasSettings = false;
        await expectLater(
          repository.getGcashDetails(),
          throwsA(isA<PaymentFlowException>()),
        );
        expect(server.uploads, isEmpty);
      },
    );
  });
}

class _PaymentServer {
  late HttpServer _server;
  String get url => 'http://127.0.0.1:${_server.port}';
  final uploads = <(String, List<int>)>[];
  final uploadTypes = <String?>[];
  final upserts = <String?>[];
  final rpcBodies = <Map<String, dynamic>>[];
  final financialWrites = <String>[];
  bool rejectUpload = false;
  int? uploadFailureStatus;
  int duplicateStatus = 409;
  Duration? delayRpc;
  bool failRpcOnce = false;
  bool hasSettings = true;
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);
  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      [],
      (all, part) => all..addAll(part),
    );
    final path = request.uri.path;
    if (path == '/auth/v1/token') {
      final expiry =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'sub': _authId, 'exp': expiry})))
          .replaceAll('=', '');
      await _respond(request, {
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': _authId,
          'aud': 'authenticated',
          'email': 'test@example.com',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      });
    } else if (path.startsWith('/storage/v1/object/payment-receipts/')) {
      // Storage uses multipart encoding; extract the file without decoding its bytes.
      final bodyText = latin1.decode(bytes);
      final fileHeader = bodyText.indexOf('filename=');
      final fileStart = bodyText.indexOf('\r\n\r\n', fileHeader) + 4;
      final boundary = request.headers.contentType!.parameters['boundary']!;
      final fileEnd = bodyText.indexOf('\r\n--$boundary', fileStart);
      uploads.add((path, bytes.sublist(fileStart, fileEnd)));
      final contentType = RegExp(
        r'content-type: ([^\r\n]+)',
        caseSensitive: false,
      ).firstMatch(bodyText.substring(0, fileStart));
      uploadTypes.add(contentType?.group(1));
      upserts.add(request.headers.value('x-upsert'));
      if (rejectUpload || uploadFailureStatus != null) {
        request.response.statusCode = uploadFailureStatus ?? 403;
        await _respond(request, {
          'statusCode': (uploadFailureStatus ?? 403).toString(),
          'error': 'Forbidden',
          'message': 'Upload denied',
        });
      } else if (uploads.length > 1) {
        request.response.statusCode = duplicateStatus;
        await _respond(request, {
          'statusCode': duplicateStatus.toString(),
          'error': 'Duplicate',
          'message': 'Already exists',
        });
      } else {
        await _respond(request, {
          'Key': path.substring('/storage/v1/object/'.length),
        });
      }
    } else if (path == '/rest/v1/rpc/submit_customer_payment') {
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      rpcBodies.add(body);
      if (delayRpc case final delay?) await Future<void>.delayed(delay);
      if (failRpcOnce) {
        failRpcOnce = false;
        request.response.statusCode = 503;
        await _respond(request, {
          'code': 'P0001',
          'message': 'Response lost',
          'details': null,
          'hint': null,
        });
      } else {
        await _respond(request, {
          'id': body['p_request_id'] ?? _requestId,
          'transaction_id': 7,
          'method': body['p_method'],
          'status': body['p_method'] == 'gcash' ? 'pending' : 'pay_at_shop',
          'amount': 600,
          'receipt_path': body['p_receipt_path'],
        });
      }
    } else if (path == '/rest/v1/transactions') {
      await _respond(request, [
        {
          'id': 7,
          'customer_id': 'customer-1',
          'total_amount': 1000,
          'payment_status': 'Paid',
        },
      ]);
    } else if (path == '/rest/v1/customer_payment_settings') {
      await _respond(
        request,
        hasSettings
            ? [
                {
                  'id': 1,
                  'gcash_qr_image_url': 'https://shop.test/qr.png',
                  'gcash_recipient_name': 'Repair shop',
                },
              ]
            : [],
      );
    } else {
      if (request.method != 'GET') financialWrites.add(path);
      request.response.statusCode = 404;
      await _respond(request, {
        'code': '404',
        'message': 'Unexpected test route',
      });
    }
  }

  Future<void> _respond(HttpRequest request, Object body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

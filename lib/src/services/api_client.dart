import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/pools/pool.dart';
import '../models/api_models.dart';
import '../models/api_exceptions.dart';
import '../models/crypto_send_models.dart';
import '../models/pocket_models.dart';
import '../models/savings_models.dart';

class ApiClient {
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;

  static const _tokenKey = 'zend_session_token';

  ApiClient({
    required String baseUrl,
    required FlutterSecureStorage secureStorage,
    Dio? dio,
  })  : _secureStorage = secureStorage,
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 15)
      ..headers['Content-Type'] = 'application/json';

    _dio.interceptors.add(_buildInterceptor());
  }

  QueuedInterceptorsWrapper _buildInterceptor() {
    return QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _secureStorage.read(key: _tokenKey);
        if (token?.isNotEmpty ?? false) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.type == DioExceptionType.connectionError) {
          handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              error: NetworkException(),
              type: error.type,
            ),
          );
          return;
        }

        if (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout) {
          handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              error: RequestTimeoutException(),
              type: error.type,
            ),
          );
          return;
        }

        final response = error.response;

        if (response?.statusCode == 401) {
          _secureStorage.delete(key: _tokenKey);
        }

        if (response?.data is Map<String, dynamic>) {
          final body = response!.data as Map<String, dynamic>;
          if (body.containsKey('error') && body.containsKey('message')) {
            handler.reject(
              DioException(
                requestOptions: error.requestOptions,
                response: response,
                error: ApiException(
                  statusCode: response.statusCode ?? 500,
                  errorCode: body['error'] as String,
                  rawMessage: body['message'] as String,
                ),
                type: error.type,
              ),
            );
            return;
          }
        }

        handler.reject(
          DioException(
            requestOptions: error.requestOptions,
            response: response,
            error: ApiException(
              statusCode: response?.statusCode ?? 500,
              errorCode: 'UNKNOWN_ERROR',
              rawMessage: error.message ?? 'An unknown error occurred',
            ),
            type: error.type,
          ),
        );
      },
    );
  }

  Future<OtpResponse> requestOtp(String phoneNumber) async {
    try {
      final response = await _dio.post(
        '/api/zend/auth/otp/request',
        data: {'phone_number': phoneNumber},
      );
      return OtpResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<OtpResponse> requestOtpByEmail(String email) async {
    try {
      final response = await _dio.post(
        '/api/zend/auth/otp/request',
        data: {'email': email},
      );
      return OtpResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<PrepareTransferResponse> prepareTransfer({
    required String recipientZendtag,
    required double amountUsdc,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/transfer/prepare',
        data: {
          'recipient_zendtag': recipientZendtag,
          'amount_usdc': amountUsdc,
        },
        options: Options(
          // ATA creation for first-time recipients can take 15-30s
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return PrepareTransferResponse.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<OtpVerifyResponse> verifyOtp(String sessionId, String code) async {
    try {
      final response = await _dio.post(
        '/api/zend/auth/otp/verify',
        data: {'session_id': sessionId, 'code': code},
      );
      return OtpVerifyResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<RegisterResponse> register(
    String verificationToken,
    String displayName,
    String zendtag,
  ) async {
    try {
      final response = await _dio.post(
        '/api/zend/auth/register',
        data: {
          'verification_token': verificationToken,
          'display_name': displayName,
          'zendtag': zendtag,
        },
      );
      return RegisterResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<AuthResponse> signIn(String verificationToken) async {
    try {
      final response = await _dio.post(
        '/api/zend/auth/signin',
        data: {'verification_token': verificationToken},
      );
      return AuthResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<ZendtagCheckResponse> checkZendtag(String tag) async {
    try {
      final response = await _dio.get(
        '/api/zend/zendtag/check',
        queryParameters: {'tag': tag},
      );
      return ZendtagCheckResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<ZendtagResolveResponse> resolveZendtag(String tag) async {
    try {
      final response = await _dio.get('/api/zend/zendtag/resolve/$tag');
      return ZendtagResolveResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<BackupResponse> storeBackup(
    String encryptedKeypairB64,
    String nonceB64,
    String publicKey,
  ) async {
    try {
      final response = await _dio.post(
        '/api/zend/wallet/backup',
        data: {
          'encrypted_keypair': encryptedKeypairB64,
          'nonce': nonceB64,
          'public_key': publicKey,
        },
      );
      return BackupResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<RetrieveBackupResponse> retrieveBackup() async {
    try {
      final response = await _dio.get('/api/zend/wallet/backup');
      return RetrieveBackupResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<BalanceResponse> getBalance() async {
    try {
      final response = await _dio.get('/api/zend/wallet/balance');
      return BalanceResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<TransferResponse> submitTransfer(
    String recipientZendtag,
    double amountUsdc,
    String partiallySignedTxB64,
    String? note,
  ) async {
    try {
      final response = await _dio.post(
        '/api/zend/transfer',
        data: {
          'recipient_zendtag': recipientZendtag,
          'amount_usdc': amountUsdc,
          'partially_signed_tx': partiallySignedTxB64,
          'note': note,
        }..removeWhere((_, v) => v == null),
        options: Options(
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return TransferResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<TransferHistoryResponse> getTransferHistory({
    String? cursor,
    int? limit,
  }) async {
    try {
      final response = await _dio.get(
        '/api/zend/transfer/history',
        queryParameters: <String, dynamic>{
          'cursor': cursor,
          'limit': limit,
        }..removeWhere((_, v) => v == null),
      );
      return TransferHistoryResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<FxPreviewResponse> getFxPreview(double amountUsd) async {
    try {
      final response = await _dio.get(
        '/api/zend/fx/preview',
        queryParameters: {'amount_usd': amountUsd},
      );
      return FxPreviewResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw e.error ?? e;
      }
    }

  Future<UserProfileResponse> getCurrentUser() async {
    try {
      final response = await _dio.get('/api/zend/user/me');
      return UserProfileResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<void> registerFcmToken(String fcmToken) async {
    try {
      await _dio.post(
        '/api/zend/devices/register',
        data: {'fcm_token': fcmToken},
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> createPaymentRequest({
    double? amountUsdc,
    String? description,
    DateTime? expiresAt,
    String? recipientZendtag,
    String? recipientEmail,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/payment-requests',
        data: {
          'amount_usdc': amountUsdc,
          'description': description,
          'expires_at': expiresAt?.toIso8601String(),
          'recipient_zendtag': recipientZendtag,
          'recipient_email': recipientEmail,
        }..removeWhere((_, v) => v == null),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> getPaymentRequests({String? status}) async {
    try {
      final response = await _dio.get(
        '/api/zend/payment-requests',
        queryParameters: <String, dynamic>{
          'status': status,
        }..removeWhere((_, v) => v == null),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<void> cancelPaymentRequest(String id) async {
    try {
      await _dio.delete('/api/zend/payment-requests/$id');
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> getBankSendNgnRates() async {
    try {
      final response = await _dio.get('/api/zend/bank-send/ngn/rates');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<List<dynamic>> getBankSendNgnBanks() async {
    try {
      final response = await _dio.get('/api/zend/bank-send/ngn/banks');
      final data = response.data as Map<String, dynamic>;
      return data['banks'] as List<dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> resolveNgnBankAccount({
    required String bankId,
    required String accountNumber,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/bank-send/ngn/resolve-account',
        data: {'bank_id': bankId, 'account_number': accountNumber},
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> prepareNgnBankSend({
    required double amountUsdc,
    required String bankId,
    required String accountNumber,
    String? savedAccountId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/bank-send/ngn/prepare',
        data: <String, dynamic>{
          'amount_usdc': amountUsdc,
          'bank_id': bankId,
          'account_number': accountNumber,
          'saved_account_id': savedAccountId,
        }..removeWhere((_, v) => v == null),
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> confirmBankSend({
    required String orderId,
    required String partiallySignedTx,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/bank-send/ngn/confirm',
        data: {
          'order_id': orderId,
          'partially_signed_tx': partiallySignedTx,
        },
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<List<dynamic>> getIntlSavedAccounts() async {
    try {
      final response =
          await _dio.get('/api/zend/bank-send/intl/saved-accounts');
      final data = response.data as Map<String, dynamic>;
      return data['accounts'] as List<dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> addIntlBankAccount(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(
        '/api/zend/bank-send/intl/add-account',
        data: data,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> prepareIntlBankSend({
    required double amountUsdc,
    required String savedAccountId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/bank-send/intl/prepare',
        data: {
          'amount_usdc': amountUsdc,
          'saved_account_id': savedAccountId,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> confirmIntlBankSend({
    required String orderId,
    required String partiallySignedTx,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/bank-send/intl/confirm',
        data: {
          'order_id': orderId,
          'partially_signed_tx': partiallySignedTx,
        },
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<List<dynamic>> getBankSendOrders() async {
    try {
      final response = await _dio.get('/api/zend/bank-send/orders');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<List<dynamic>> getPayinOrders() async {
    try {
      final response = await _dio.get('/api/zend/payin/orders');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<List<dynamic>> getCryptoDepositHistory() async {
    try {
      final response = await _dio.get('/api/zend/crypto/deposits');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> getBridgeKycStatus() async {
    try {
      final response = await _dio.get('/api/zend/bridge/kyc/status');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> startBridgeKyc() async {
    try {
      final response = await _dio.post('/api/zend/bridge/kyc/start');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> getMyPageCustomisation() async {    try {
      final response = await _dio.get('/api/zend/page/customisation');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> updateMyPageCustomisation(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.put(
        '/api/zend/page/customisation',
        data: data,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  // ── Pools v2 ────────────────────────────────────────────────────────────────

  Future<Pool> createPool({
    required String name,
    required double targetAmountUsdc,
    DateTime? deadline,
    required List<Map<String, dynamic>> participants,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/pools',
        data: <String, dynamic>{
          'name': name,
          'target_amount_usdc': targetAmountUsdc,
          'deadline': deadline?.toUtc().toIso8601String(),
          'participants': participants,
        }..removeWhere((_, v) => v == null),
      );
      return Pool.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<List<Pool>> listPools({String? cursor, int? limit}) async {
    try {
      final response = await _dio.get(
        '/api/zend/pools',
        queryParameters: <String, dynamic>{
          'cursor': cursor,
          'limit': limit,
        }..removeWhere((_, v) => v == null),
      );
      final data = response.data as Map<String, dynamic>;
      final pools = (data['pools'] as List<dynamic>? ?? [])
          .map((p) => Pool.fromJson(p as Map<String, dynamic>))
          .toList();
      return pools;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Pool> getPool(String poolId) async {
    try {
      final response = await _dio.get('/api/zend/pools/$poolId');
      return Pool.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<void> cancelPool(String poolId) async {
    try {
      await _dio.delete('/api/zend/pools/$poolId');
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<PrepareTransferResponse> prepareContribution({
    required String poolId,
    required double amountUsdc,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/pools/$poolId/contribute/prepare',
        data: {'amount_usdc': amountUsdc},
        options: Options(
          // ATA creation can take 15-30s for first-time recipients
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return PrepareTransferResponse.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<Map<String, dynamic>> submitContribution({
    required String poolId,
    required double amountUsdc,
    required String partiallySignedTx,
    String? note,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/pools/$poolId/contribute',
        data: <String, dynamic>{
          'amount_usdc': amountUsdc,
          'partially_signed_tx': partiallySignedTx,
          'note': note,
        }..removeWhere((_, v) => v == null),
        options: Options(
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<List<PoolMessage>> listMessages({
    required String poolId,
    String? beforeId,
    int? limit,
  }) async {
    try {
      final response = await _dio.get(
        '/api/zend/pools/$poolId/messages',
        queryParameters: <String, dynamic>{
          'before_id': beforeId,
          'limit': limit,
        }..removeWhere((_, v) => v == null),
      );
      final data = response.data as Map<String, dynamic>;
      return (data['messages'] as List<dynamic>? ?? [])
          .map((m) => PoolMessage.fromJson(m as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<PoolMessage> postMessage({
    required String poolId,
    required String content,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/pools/$poolId/messages',
        data: {'content': content},
      );
      return PoolMessage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<PoolMessage> postVoiceNote({
    required String poolId,
    required List<int> audioBytes,
    required String mimeType,
    required int durationSeconds,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/pools/$poolId/messages/voice',
        queryParameters: {'duration_seconds': durationSeconds},
        data: audioBytes,
        options: Options(
          contentType: mimeType,
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );
      return PoolMessage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<void> addReaction({
    required String poolId,
    required String messageId,
    required String emoji,
  }) async {
    try {
      await _dio.post(
        '/api/zend/pools/$poolId/messages/$messageId/react',
        data: {'emoji': emoji},
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<void> removeReaction({
    required String poolId,
    required String messageId,
    required String emoji,
  }) async {
    try {
      await _dio.delete(
        '/api/zend/pools/$poolId/messages/$messageId/react',
        data: {'emoji': emoji},
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  // ── Savings ─────────────────────────────────────────────────────────────────

  Future<SavingsMetrics> getSavingsMetrics() async {
    try {
      final response = await _dio.get('/api/zend/savings/metrics');
      return SavingsMetrics.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsPosition> getSavingsPosition() async {
    try {
      final response = await _dio.get('/api/zend/savings/position');
      return SavingsPosition.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsPrepareResponse> prepareSavingsDeposit(
      double amountUsdc, {
      String? pocketId,
  }) async {
    try {
      final data = <String, dynamic>{'amount_usdc': amountUsdc};
      if (pocketId != null) data['pocket_id'] = pocketId;
      final response = await _dio.post(
        '/api/zend/savings/deposit/prepare',
        data: data,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return SavingsPrepareResponse.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsSubmitResult> submitSavingsDeposit(
      String partiallySignedTxB64, {
      String? pocketId,
  }) async {
    try {
      final data = <String, dynamic>{
        'partially_signed_tx': partiallySignedTxB64,
      };
      if (pocketId != null) data['pocket_id'] = pocketId;
      final response = await _dio.post(
        '/api/zend/savings/deposit/submit',
        data: data,
        options: Options(
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return SavingsSubmitResult.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsPrepareResponse> prepareSavingsWithdraw() async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/withdraw/prepare',
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return SavingsPrepareResponse.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsSubmitResult> submitSavingsWithdraw(
      String partiallySignedTxB64) async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/withdraw/submit',
        data: {'partially_signed_tx': partiallySignedTxB64},
        options: Options(
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return SavingsSubmitResult.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  // ── Savings Pockets ─────────────────────────────────────────────────────────

  Future<List<SavingsPocket>> listPockets() async {
    try {
      final response = await _dio.get(
        '/api/zend/savings/pockets',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      final data = response.data as List<dynamic>;
      return data
          .map((p) => SavingsPocket.fromJson(p as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsPocket> getPocket(String id) async {
    try {
      final response = await _dio.get(
        '/api/zend/savings/pockets/$id',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      return SavingsPocket.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsPocket> createGoal(CreateGoalRequest req) async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/pockets/goals',
        data: req.toJson(),
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      return SavingsPocket.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<void> deleteGoal(String id) async {
    try {
      await _dio.delete(
        '/api/zend/savings/pockets/goals/$id',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsPocket> createLock(CreateLockRequest req) async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/pockets/lock',
        data: req.toJson(),
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      return SavingsPocket.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsPrepareResponse> prepareFreeWithdraw(double amountUsd) async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/pockets/free/withdraw/prepare',
        data: {'amount_usd': amountUsd},
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return SavingsPrepareResponse.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsSubmitResult> submitFreeWithdraw(String signedTx) async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/pockets/free/withdraw/submit',
        data: {'partially_signed_tx': signedTx},
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      return SavingsSubmitResult.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsPrepareResponse> prepareGoalWithdraw(String pocketId) async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/pockets/goals/$pocketId/withdraw/prepare',
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return SavingsPrepareResponse.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsSubmitResult> submitGoalWithdraw(
      String pocketId, String signedTx) async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/pockets/goals/$pocketId/withdraw/submit',
        data: {'partially_signed_tx': signedTx},
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      return SavingsSubmitResult.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsPrepareResponse> prepareLockWithdraw() async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/pockets/lock/withdraw/prepare',
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return SavingsPrepareResponse.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<SavingsSubmitResult> submitLockWithdraw(String signedTx) async {
    try {
      final response = await _dio.post(
        '/api/zend/savings/pockets/lock/withdraw/submit',
        data: {'partially_signed_tx': signedTx},
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      return SavingsSubmitResult.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  // ── NGN Saved Accounts ───────────────────────────────────────────────────────

  Future<List<dynamic>> getNgnSavedAccounts() async {
    try {
      final response = await _dio.get('/api/zend/bank-send/ngn/saved-accounts');
      final data = response.data as Map<String, dynamic>;
      return data['accounts'] as List<dynamic>;
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<void> deleteNgnSavedAccount(String accountId) async {
    try {
      await _dio.delete('/api/zend/bank-send/ngn/saved-accounts/$accountId');
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  // ── Multichain Crypto Rails ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSupportedChains() async {
    try {
      final resp = await _dio.get('/api/v1/public/chains');
      return (resp.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<void> setOnboardingChains(List<int> chainIds) async {
    try {
      await _dio.post('/api/zend/crypto/onboarding-chains', data: {
        'chain_ids': chainIds,
      });
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<CryptoSendQuote> getCryptoSendQuote({
    required int chainId,
    required String destinationAddress,
    required double amountUsdc,
  }) async {
    try {
      final resp = await _dio.post('/api/zend/crypto/send/quote', data: {
        'chain_id': chainId,
        'destination_address': destinationAddress,
        'amount_usdc': amountUsdc,
      });
      return CryptoSendQuote.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  Future<CryptoSendResult> executeCryptoSend({
    required String quoteId,
  }) async {
    try {
      final resp = await _dio.post('/api/zend/crypto/send/execute', data: {
        'quote_id': quoteId,
      });
      return CryptoSendResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  // ── QR Pay — public request link resolution ─────────────────────────────────

  /// Fetches the public details of a payment request link.
  ///
  /// Returns [RequestLinkDetails] on success (HTTP 200).
  /// Throws [ApiException] with statusCode 404 if the request is not found,
  /// expired, or no longer pending.
  Future<RequestLinkDetails> getPublicUserRequestData(
    String zendtag,
    String requestLinkId,
  ) async {
    try {
      final resp = await _dio.get(
        '/api/v1/public/zend/$zendtag/$requestLinkId',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      return RequestLinkDetails.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }
}

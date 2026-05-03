import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/api_models.dart';
import '../models/api_exceptions.dart';

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

  /// POST /api/zend/transfer/prepare
  /// Step 1 of the two-step transfer flow.
  /// Returns blockhash, recipient_wallet_address, fee_payer, ata_created.
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
      // Use a longer timeout for transfers — ATA creation for first-time
      // recipients can take 15-30s on mainnet (backend pays the fee).
      // The global timeout is 15s which is too short for this case.
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

  /// Register or refresh the FCM device token with the backend.
  /// Called after login and whenever FCM issues a new token.
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

  // ── Payment requests ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createPaymentRequest({
    double? amountUsdc,
    String? description,
    DateTime? expiresAt,
  }) async {
    try {
      final response = await _dio.post(
        '/api/zend/payment-requests',
        data: {
          'amount_usdc': amountUsdc,
          'description': description,
          'expires_at': expiresAt?.toIso8601String(),
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

  // ── Bank send ─────────────────────────────────────────────────────────────

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

  // ── Page customisation ────────────────────────────────────────────────────

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
}

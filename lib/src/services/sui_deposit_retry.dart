import '../models/api_exceptions.dart';
import 'payment_rail_models.dart';
import 'sui_zklogin_service.dart';

/// Money that just arrived (a top-up, a deposit from outside Zend) sits in a
/// separate coin until it's moved into the balance, and anything that spends
/// from the balance can't use it yet. The server says so with
/// `SUI_ADDRESS_BALANCE_INSUFFICIENT` before building anything. Move it in
/// and try once more, without asking the person: the same step plain sends
/// already take.
Future<T> withSuiDepositRetry<T>(
  SuiZkLoginService zkLogin,
  Future<T> Function() prepare,
) async {
  try {
    return await prepare();
  } on ApiException catch (e) {
    if (e.errorCode != 'SUI_ADDRESS_BALANCE_INSUFFICIENT') rethrow;
    await zkLogin.depositCoinObjectsToAddressBalance(
      rail: PaymentRail.sui,
      network: kSuiNetwork,
    );
    return prepare();
  }
}

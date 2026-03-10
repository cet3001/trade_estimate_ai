import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IapService extends ChangeNotifier {
  static final IapService _instance = IapService._internal();
  factory IapService() => _instance;
  IapService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  static const String kSubscriptionMonthly =
      'com.blackstonerow.tradeestimateai.subscription.monthly';
  static const String kCredits5 =
      'com.blackstonerow.tradeestimateai.credits.5';
  static const String kCredits15 =
      'com.blackstonerow.tradeestimateai.credits.15';

  static const Set<String> _productIds = {
    kSubscriptionMonthly,
    kCredits5,
    kCredits15,
  };

  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  bool _purchasePending = false;
  bool get purchasePending => _purchasePending;

  String? _lastError;
  String? get lastError => _lastError;

  // Called from main.dart during app startup
  Future<void> initialize() async {
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint('[IAP] Store not available');
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (Object error) {
        debugPrint('[IAP] Purchase stream error: $error');
        _lastError = error.toString();
        notifyListeners();
      },
    );

    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    final ProductDetailsResponse response =
        await _iap.queryProductDetails(_productIds);

    if (response.error != null) {
      debugPrint('[IAP] Product load error: ${response.error}');
    }
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('[IAP] Products not found: ${response.notFoundIDs}');
    }

    _products = response.productDetails;
    notifyListeners();
  }

  ProductDetails? getProduct(String productId) {
    try {
      return _products.firstWhere((p) => p.id == productId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> buySubscription() async {
    final product = getProduct(kSubscriptionMonthly);
    if (product == null) {
      _lastError = 'Subscription product not available';
      notifyListeners();
      return false;
    }
    return _purchase(product, consumable: false);
  }

  Future<bool> buyCredits(int count) async {
    final productId = count == 5 ? kCredits5 : kCredits15;
    final product = getProduct(productId);
    if (product == null) {
      _lastError = '$count-credit pack not available';
      notifyListeners();
      return false;
    }
    return _purchase(product, consumable: true);
  }

  Future<bool> _purchase(ProductDetails product, {required bool consumable}) async {
    _lastError = null;
    _purchasePending = true;
    notifyListeners();

    try {
      final PurchaseParam param = PurchaseParam(productDetails: product);
      bool result;
      if (consumable) {
        result = await _iap.buyConsumable(purchaseParam: param);
      } else {
        result = await _iap.buyNonConsumable(purchaseParam: param);
      }
      return result;
    } catch (e) {
      _lastError = e.toString();
      _purchasePending = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> restorePurchases() async {
    _lastError = null;
    _purchasePending = true;
    notifyListeners();
    await _iap.restorePurchases();
  }

  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        // Nothing to do — UI already shows pending state
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        _lastError = purchase.error?.message ?? 'Purchase failed';
        _purchasePending = false;
        notifyListeners();
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _verifyAndGrant(purchase);
      } else if (purchase.status == PurchaseStatus.canceled) {
        _purchasePending = false;
        notifyListeners();
      }

      // Always complete the purchase to remove it from the queue
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyAndGrant(PurchaseDetails purchase) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('[IAP] No authenticated user — cannot grant purchase');
      _purchasePending = false;
      notifyListeners();
      return;
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'verify-iap-receipt',
        body: {
          'transaction_id': purchase.purchaseID,
          'product_id': purchase.productID,
          'user_id': user.id,
        },
      );

      if (response.status != 200) {
        _lastError = 'Server verification failed (${response.status})';
        debugPrint('[IAP] Verification failed: ${response.data}');
      } else {
        debugPrint('[IAP] Purchase verified: ${purchase.productID}');
      }
    } catch (e) {
      _lastError = 'Verification error: $e';
      debugPrint('[IAP] Verification error: $e');
    } finally {
      _purchasePending = false;
      notifyListeners();
    }
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

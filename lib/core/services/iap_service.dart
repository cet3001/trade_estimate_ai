import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IapService {
  static final IapService _instance = IapService._internal();
  factory IapService() => _instance;
  IapService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Cached products to avoid redundant network calls
  List<ProductDetails>? _cachedProducts;

  // Callbacks
  void Function(PurchaseDetails)? onPurchaseSuccess;
  void Function(String)? onPurchaseError;

  static const Set<String> productIds = {
    'com.blackstonerow.tradeestimateai.subscription.monthly',
    'com.blackstonerow.tradeestimateai.credits.5',
    'com.blackstonerow.tradeestimateai.credits.15',
  };

  Future<void> initialize() async {
    final isAvailable = await _iap.isAvailable();
    if (!isAvailable) return;

    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (Object error) {
        onPurchaseError?.call(error.toString());
      },
    );

    // Pre-warm the product cache
    await loadProducts();
  }

  Future<List<ProductDetails>> loadProducts() async {
    if (_cachedProducts != null) return _cachedProducts!;
    final response = await _iap.queryProductDetails(productIds);
    _cachedProducts = response.productDetails;
    return _cachedProducts!;
  }

  Future<void> buySubscription() async {
    final products = await loadProducts();
    final subscription = products.firstWhere(
      (p) => p.id.contains('subscription'),
      orElse: () => throw Exception(
        'Subscription product not found. Check App Store Connect configuration.',
      ),
    );
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: subscription),
    );
  }

  Future<void> buyCredits(int count) async {
    final products = await loadProducts();
    final credits = products.firstWhere(
      (p) => p.id.contains('credits.$count'),
      orElse: () => throw Exception(
        'Credits product for count $count not found. Check App Store Connect configuration.',
      ),
    );
    await _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: credits),
    );
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  void _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          await _verifyAndGrant(purchase);
          onPurchaseSuccess?.call(purchase);
        } catch (e) {
          onPurchaseError?.call('Failed to verify purchase: $e');
        } finally {
          // Always complete the purchase to prevent re-delivery
          await _iap.completePurchase(purchase);
        }
      } else if (purchase.status == PurchaseStatus.error) {
        onPurchaseError?.call(purchase.error?.message ?? 'Purchase failed');
      }
    }
  }

  Future<void> _verifyAndGrant(PurchaseDetails purchase) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Cannot verify purchase: no authenticated user');
    }
    await client.functions.invoke('verify-iap-receipt', body: {
      'transaction_id': purchase.purchaseID,
      'product_id': purchase.productID,
      'user_id': userId,
    });
  }

  void dispose() {
    _subscription?.cancel();
  }
}

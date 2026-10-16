import 'marketplace_home.dart';

/// Stato di presentazione dei due slider, prodotto dal controller.
class MarketplaceDiscoveryState {
  const MarketplaceDiscoveryState({
    this.data,
    this.isLoading = false,
    this.hasError = false,
  });

  final MarketplaceHomeData? data;
  final bool isLoading;
  final bool hasError;

  List<MarketplaceExpansion> get expansions => data?.expansions ?? const [];
  List<MarketplaceCardPreview> get topSellers => data?.topSellers ?? const [];
  bool get expansionsLoading =>
      isLoading && expansions.isEmpty && (data?.expansionsLoading ?? true);
  bool get topSellersLoading =>
      isLoading && topSellers.isEmpty && (data?.topSellersLoading ?? true);
  bool get expansionsUnavailable =>
      hasError || (data?.expansionsUnavailable ?? false);
  bool get topSellersUnavailable =>
      hasError || (data?.topSellersUnavailable ?? false);
}

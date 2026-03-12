import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/trade_templates.dart';
import '../../core/models/estimate.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/formatters.dart';

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class EstimateHistoryScreen extends StatefulWidget {
  const EstimateHistoryScreen({super.key});

  @override
  State<EstimateHistoryScreen> createState() => _EstimateHistoryScreenState();
}

class _EstimateHistoryScreenState extends State<EstimateHistoryScreen> {
  final _service = SupabaseService();

  // -- Data
  List<Estimate> _allEstimates = [];
  bool _isLoading = true;
  String? _loadError;

  // -- Busy guard (prevents concurrent delete/duplicate)
  bool _isBusy = false;

  // -- Trade filter: null = All
  TradeType? _tradeFilter;

  // -- Status filter: null = All
  String? _statusFilter;

  static const _tradeOptions = [
    TradeType.plumbing,
    TradeType.electrical,
    TradeType.roofing,
    TradeType.construction,
  ];

  static const _statusOptions = ['draft', 'sent', 'accepted', 'declined'];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadEstimates();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _loadEstimates() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final estimates = await _service.getEstimates();
      if (!mounted) return;
      setState(() {
        _allEstimates = estimates;
        _rebuildFilteredCache();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Failed to load estimates. Please try again.';
        _isLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Filtered list
  // ---------------------------------------------------------------------------

  // Cached result — rebuilt inside every setState that touches _allEstimates,
  // _tradeFilter, or _statusFilter to avoid allocating a new List on every build().
  List<Estimate> _filteredEstimates = [];

  void _rebuildFilteredCache() {
    _filteredEstimates = _allEstimates.where((e) {
      final tradeMatch = _tradeFilter == null || e.trade == _tradeFilter;
      final statusMatch = _statusFilter == null || e.status == _statusFilter;
      return tradeMatch && statusMatch;
    }).toList();
  }

  bool get _filtersActive => _tradeFilter != null || _statusFilter != null;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _deleteEstimate(Estimate estimate) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.md),
        ),
        title: Text('Delete Estimate', style: AppTextStyles.heading2),
        content: Text(
          'Delete this estimate? This cannot be undone.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: AppTextStyles.body.copyWith(color: AppColors.negative),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      if (mounted) setState(() => _isBusy = false);
      return;
    }

    try {
      await _service.deleteEstimate(estimate.id);
      if (!mounted) return;
      setState(() {
        _allEstimates.removeWhere((e) => e.id == estimate.id);
        _isBusy = false;
      });
      _showSnackBar('Estimate deleted.', isSuccess: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _showSnackBar('Failed to delete. Please try again.', isSuccess: false);
    }
  }

  Future<void> _duplicateEstimate(Estimate estimate) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      final duplicated = await _service.duplicateEstimate(estimate);
      if (!mounted) return;
      if (duplicated == null) {
        setState(() => _isBusy = false);
        _showSnackBar('Failed to duplicate. Please try again.', isSuccess: false);
        return;
      }
      setState(() => _isBusy = false);
      // Navigate to NewEstimateScreen with the duplicated estimate pre-filled
      // so the user can review and edit before regenerating.
      Navigator.of(context).pushNamed(
        '/estimate/new',
        arguments: duplicated,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _showSnackBar('Failed to duplicate. Please try again.', isSuccess: false);
    }
  }

  void _openEstimate(Estimate estimate) {
    Navigator.of(context).pushNamed(
      '/estimate/preview',
      arguments: estimate,
    );
  }

  // ---------------------------------------------------------------------------
  // Snackbar
  // ---------------------------------------------------------------------------

  void _showSnackBar(String message, {required bool isSuccess}) {
    final color = isSuccess ? AppColors.positive : AppColors.negative;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_outline : Icons.error_outline,
              color: color,
              size: AppSpacing.xl,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message, style: AppTextStyles.body)),
          ],
        ),
        backgroundColor: AppColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.lg),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: Material(
          color: AppColors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.xxl),
            onTap: () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Icon(
                Icons.chevron_left,
                color: AppColors.textPrimary,
                size: AppSpacing.xxl,
              ),
            ),
          ),
        ),
        title: Text('Estimates', style: AppTextStyles.heading2),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.positive),
        ),
      );
    }

    if (_loadError != null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      color: AppColors.positive,
      backgroundColor: AppColors.surface,
      onRefresh: _loadEstimates,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildFilterRows()),
          _buildList(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Error state
  // ---------------------------------------------------------------------------

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.negative,
              size: AppSpacing.huge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Failed to load estimates',
              style: AppTextStyles.heading2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _loadError ?? '',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              height: AppSpacing.buttonHeight,
              child: ElevatedButton(
                onPressed: _loadEstimates,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.md),
                  ),
                ),
                child: Text('Retry', style: AppTextStyles.body),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filter rows
  // ---------------------------------------------------------------------------

  Widget _buildFilterRows() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTradeFilterRow(),
          const SizedBox(height: AppSpacing.sm),
          _buildStatusFilterRow(),
        ],
      ),
    );
  }

  Widget _buildTradeFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          _FilterPill(
            label: 'All',
            isActive: _tradeFilter == null,
            onTap: () => setState(() {
              _tradeFilter = null;
              _rebuildFilteredCache();
            }),
          ),
          ..._tradeOptions.map((trade) => Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: _FilterPill(
                  label: trade.displayName,
                  isActive: _tradeFilter == trade,
                  onTap: () => setState(() {
                    _tradeFilter = _tradeFilter == trade ? null : trade;
                    _rebuildFilteredCache();
                  }),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStatusFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          _FilterPill(
            label: 'All',
            isActive: _statusFilter == null,
            onTap: () => setState(() {
              _statusFilter = null;
              _rebuildFilteredCache();
            }),
          ),
          ..._statusOptions.map((status) => Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: _FilterPill(
                  label: _statusLabel(status),
                  isActive: _statusFilter == status,
                  onTap: () => setState(() {
                    _statusFilter = _statusFilter == status ? null : status;
                    _rebuildFilteredCache();
                  }),
                ),
              )),
        ],
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      default:
        return status;
    }
  }

  // ---------------------------------------------------------------------------
  // List
  // ---------------------------------------------------------------------------

  Widget _buildList() {
    final estimates = _filteredEstimates;

    if (estimates.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == estimates.length) {
            // Bottom padding
            return const SizedBox(height: AppSpacing.huge);
          }
          final estimate = estimates[index];
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: _SlidableEstimateRow(
              key: ValueKey(estimate.id),
              estimate: estimate,
              isBusy: _isBusy,
              onTap: () => _openEstimate(estimate),
              onDuplicate: () => _duplicateEstimate(estimate),
              onDelete: () => _deleteEstimate(estimate),
            ),
          );
        },
        childCount: estimates.length + 1,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    // No estimates at all = list is empty AND no filters applied.
    // If filters are active but result is empty, show filter-specific message.
    final hasNoEstimatesAtAll = _allEstimates.isEmpty && !_filtersActive;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.description_outlined,
              color: AppColors.textTertiary,
              size: 64,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              hasNoEstimatesAtAll
                  ? 'No estimates yet.'
                  : 'No estimates match your filters.',
              style: AppTextStyles.heading2.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasNoEstimatesAtAll) ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.buttonHeight,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/estimate/new'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.positive,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.md),
                    ),
                  ),
                  child: Text(
                    'Create Your First Estimate',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.buttonHeight,
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _tradeFilter = null;
                    _statusFilter = null;
                    _rebuildFilteredCache();
                  }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.borderDefault),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.md),
                    ),
                  ),
                  child: Text(
                    'Clear Filters',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter pill
// ---------------------------------------------------------------------------

class _FilterPill extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppColors.positive : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppSpacing.xxl),
        ),
        child: Text(
          label,
          style: AppTextStyles.label.copyWith(
            color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slidable row — custom swipe to reveal Duplicate / Delete
// ---------------------------------------------------------------------------

class _SlidableEstimateRow extends StatefulWidget {
  final Estimate estimate;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _SlidableEstimateRow({
    super.key,
    required this.estimate,
    required this.isBusy,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  State<_SlidableEstimateRow> createState() => _SlidableEstimateRowState();
}

class _SlidableEstimateRowState extends State<_SlidableEstimateRow>
    with SingleTickerProviderStateMixin {
  static const double _actionButtonWidth = 80.0;
  static const double _totalActionWidth = _actionButtonWidth * 2;

  late AnimationController _controller;

  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    // Negative delta = dragging left (revealing actions)
    final delta = details.primaryDelta ?? 0;
    final currentPx = _controller.value * _totalActionWidth;
    final newPx = (currentPx - delta).clamp(0.0, _totalActionWidth);
    _controller.value = newPx / _totalActionWidth;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final openFraction = _controller.value;
    // Snap open if dragged more than half or velocity is negative (leftward)
    final velocity = details.primaryVelocity ?? 0;
    if (openFraction > 0.5 || velocity < -300) {
      _snapOpen();
    } else {
      _snapClose();
    }
  }

  void _snapOpen() {
    _isOpen = true;
    _controller.animateTo(1.0,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _snapClose() {
    _isOpen = false;
    _controller.animateTo(0.0,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _handleTile() {
    if (_isOpen) {
      _snapClose();
    } else {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: GestureDetector(
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        // Absorb vertical scrolls properly
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // -- Action buttons (revealed behind the tile)
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ActionButton(
                    label: 'Duplicate',
                    color: AppColors.accent,
                    icon: Icons.copy_outlined,
                    width: _actionButtonWidth,
                    onTap: widget.isBusy
                        ? null
                        : () {
                            _snapClose();
                            widget.onDuplicate();
                          },
                  ),
                  _ActionButton(
                    label: 'Delete',
                    color: AppColors.negative,
                    icon: Icons.delete_outline,
                    width: _actionButtonWidth,
                    onTap: widget.isBusy
                        ? null
                        : () {
                            _snapClose();
                            widget.onDelete();
                          },
                  ),
                ],
              ),
            ),

            // -- Sliding tile
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offsetPx = _controller.value * _totalActionWidth;
                return Transform.translate(
                  offset: Offset(-offsetPx, 0),
                  child: child,
                );
              },
              child: GestureDetector(
                onTap: _handleTile,
                child: _EstimateListTile(estimate: widget.estimate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action button (shown behind the sliding tile)
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final double width;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        color: color,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textPrimary, size: AppSpacing.xl),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estimate list tile
// ---------------------------------------------------------------------------

class _EstimateListTile extends StatelessWidget {
  final Estimate estimate;

  const _EstimateListTile({required this.estimate});

  @override
  Widget build(BuildContext context) {
    final total = estimate.totalEstimate ?? estimate.computedTotal;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trade icon
          Container(
            width: AppSpacing.tradeIconBadgeSize,
            height: AppSpacing.tradeIconBadgeSize,
            decoration: BoxDecoration(
              color: estimate.trade.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.sm),
            ),
            child: Icon(
              _tradeIcon(estimate.trade),
              color: estimate.trade.color,
              size: AppSpacing.xl,
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Job info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + status badge row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        estimate.jobTitle ?? 'Untitled Estimate',
                        style: AppTextStyles.heading2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _StatusBadge(status: estimate.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),

                // Client name
                Text(
                  estimate.clientName ?? 'No client',
                  style: AppTextStyles.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),

                // Date + total row
                Row(
                  children: [
                    Text(
                      Formatters.date(estimate.createdAt),
                      style: AppTextStyles.caption,
                    ),
                    const Spacer(),
                    Text(
                      Formatters.currency(total),
                      style: AppTextStyles.totalAmountSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _tradeIcon(TradeType trade) {
    switch (trade) {
      case TradeType.plumbing:
        return Icons.plumbing;
      case TradeType.electrical:
        return Icons.bolt;
      case TradeType.roofing:
        return Icons.house_outlined;
      case TradeType.construction:
        return Icons.construction;
    }
  }
}

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case 'sent':
        color = AppColors.accent;
        label = 'Sent';
      case 'accepted':
        color = AppColors.positive;
        label = 'Accepted';
      case 'declined':
        color = AppColors.negative;
        label = 'Declined';
      default:
        color = AppColors.textTertiary;
        label = 'Draft';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.cardBorderRadius),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/models/estimate.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/email_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/formatters.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class EstimatePreviewScreen extends StatefulWidget {
  /// Full [Estimate] object passed directly (preferred — avoids a round-trip).
  final Estimate? estimate;

  /// Fallback: fetch the estimate by ID when [estimate] is not provided.
  final String estimateId;

  EstimatePreviewScreen({
    super.key,
    this.estimate,
    this.estimateId = '',
  }) : assert(
          estimate != null || estimateId.isNotEmpty,
          'EstimatePreviewScreen requires either an estimate object or a non-empty estimateId',
        );

  @override
  State<EstimatePreviewScreen> createState() => _EstimatePreviewScreenState();
}

class _EstimatePreviewScreenState extends State<EstimatePreviewScreen> {
  // ---- Data
  Estimate? _estimate;
  UserProfile? _profile;

  // ---- Loading
  bool _isLoading = true;
  String? _loadError;

  // ---- Edit mode
  bool _isEditMode = false;
  bool _isSaving = false;
  final _bodyController = TextEditingController();

  // ---- Action buttons
  bool _isPdfLoading = false;
  bool _isEmailLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Data loading
  // --------------------------------------------------------------------------

  Future<void> _loadData() async {
    try {
      final service = SupabaseService();

      // Load estimate
      Estimate? est = widget.estimate;
      if (est == null && widget.estimateId.isNotEmpty) {
        est = await service.getEstimate(widget.estimateId);
      }

      // Load profile
      final profile = await service.getProfile();

      if (!mounted) return;
      setState(() {
        _estimate = est;
        _profile = profile;
        _bodyController.text = est?.aiGeneratedBody ?? '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  // --------------------------------------------------------------------------
  // Edit helpers
  // --------------------------------------------------------------------------

  void _toggleEditMode() {
    if (_isEditMode) {
      _saveBody();
    } else {
      setState(() => _isEditMode = true);
    }
  }

  Future<void> _saveBody() async {
    final estimate = _estimate;
    if (estimate == null) return;

    setState(() => _isSaving = true);

    try {
      final service = SupabaseService();
      await service.updateEstimateBody(
        estimate.id,
        _bodyController.text,
      );

      if (!mounted) return;
      setState(() {
        _estimate = estimate.copyWith(aiGeneratedBody: _bodyController.text);
        _isEditMode = false;
        _isSaving = false;
      });
      _showSnackBar('Saved', isSuccess: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnackBar('Failed to save. Please try again.', isSuccess: false);
    }
  }

  // --------------------------------------------------------------------------
  // PDF action
  // --------------------------------------------------------------------------

  Future<void> _handleDownloadPdf() async {
    final estimate = _estimate;
    final profile = _profile;
    if (estimate == null || profile == null) return;
    if (_isPdfLoading || _isEmailLoading) return;

    setState(() => _isPdfLoading = true);

    try {
      final file = await PdfService.generatePdf(estimate, profile);

      // Upload to Supabase Storage and update pdf_url
      try {
        final service = SupabaseService();
        final bytes = await file.readAsBytes();
        final url = await service.uploadEstimatePdf(
          estimateId: estimate.id,
          bytes: bytes,
        );
        await service.updateEstimatePdfUrl(estimate.id, url);

        if (mounted) {
          setState(() {
            _estimate = estimate.copyWith(pdfUrl: url);
          });
        }
      } catch (_) {
        // Upload failure is non-fatal — the file is still shareable locally.
      }

      // iOS share sheet
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Estimate for ${estimate.clientName ?? "Client"}',
        ),
      );

      if (!mounted) return;
      _showSnackBar('PDF ready', isSuccess: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to generate PDF. Please try again.', isSuccess: false);
    } finally {
      if (mounted) setState(() => _isPdfLoading = false);
    }
  }

  // --------------------------------------------------------------------------
  // Email action
  // --------------------------------------------------------------------------

  Future<void> _handleEmailToClient() async {
    final estimate = _estimate;
    if (estimate == null) return;
    if (_isPdfLoading || _isEmailLoading) return;

    final recipientEmail = estimate.clientEmail;
    if (recipientEmail == null || recipientEmail.isEmpty) {
      _showSnackBar('No client email on this estimate.', isSuccess: false);
      return;
    }

    setState(() => _isEmailLoading = true);

    try {
      final service = SupabaseService();
      await EmailService().sendEstimateToClient(
        estimateId: estimate.id,
        recipientEmail: recipientEmail,
        recipientName: estimate.clientName ?? '',
      );

      await service.updateEstimateStatus(estimate.id, 'sent');

      if (!mounted) return;
      setState(() {
        _estimate = estimate.copyWith(
          status: 'sent',
          sentAt: DateTime.now(),
        );
      });
      _showSnackBar('Sent!', isSuccess: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to send. Please try again.', isSuccess: false);
    } finally {
      if (mounted) setState(() => _isEmailLoading = false);
    }
  }

  // --------------------------------------------------------------------------
  // Snackbar helper
  // --------------------------------------------------------------------------

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          side: BorderSide(color: color, width: AppSpacing.previewSnackBorderWidth),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.lg),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.positive),
          ),
        ),
      );
    }

    if (_loadError != null || _estimate == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              _loadError ?? 'Estimate not found.',
              style: AppTextStyles.body.copyWith(color: AppColors.negative),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final estimate = _estimate!;
    final bool anyLoading = _isPdfLoading || _isEmailLoading || _isSaving;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBusinessHeader(estimate),
                    _buildDivider(),
                    _buildClientBlock(estimate),
                    _buildDivider(),
                    _buildEstimateBody(estimate),
                    _buildDivider(),
                    _buildCostSummary(estimate),
                    _buildDivider(),
                    _buildTerms(),
                    // Bottom spacing above fixed bar
                    const SizedBox(height: AppSpacing.buttonHeight + AppSpacing.xl),
                  ],
                ),
              ),
            ),
            // Fixed bottom action bar
            _buildBottomBar(anyLoading),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // AppBar
  // --------------------------------------------------------------------------

  AppBar _buildAppBar() {
    final bool anyLoading = _isPdfLoading || _isEmailLoading || _isSaving;
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      leading: Material(
        color: AppColors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.xxl),
          onTap: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: Icon(Icons.chevron_left, color: AppColors.textPrimary, size: AppSpacing.xxl),
          ),
        ),
      ),
      title: Text('Estimate Preview', style: AppTextStyles.heading2),
      centerTitle: true,
      actions: [
        if (_estimate != null)
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.textPrimary),
            onPressed: anyLoading ? null : _handleDownloadPdf,
            tooltip: 'Share',
          ),
        if (_estimate != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Material(
              color: AppColors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.sm),
                onTap: anyLoading ? null : _toggleEditMode,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: AppSpacing.xl,
                          height: AppSpacing.xl,
                          child: CircularProgressIndicator(
                            strokeWidth: AppSpacing.progressStrokeWidth,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                          ),
                        )
                      : Text(
                          _isEditMode ? 'Save' : 'Edit',
                          style: AppTextStyles.body.copyWith(color: AppColors.accent),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Business header
  // --------------------------------------------------------------------------

  Widget _buildBusinessHeader(Estimate estimate) {
    final profile = _profile;
    final businessName = profile?.companyName ?? profile?.fullName ?? 'Your Business';
    final phone = profile?.phone;
    final email = profile?.email;
    final license = profile?.licenseNumber;

    final contactParts = <String>[];
    if (phone != null && phone.isNotEmpty) contactParts.add(phone);
    if (email != null && email.isNotEmpty) contactParts.add(email);
    final contactLine = contactParts.join(' | ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: business info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(businessName, style: AppTextStyles.heading2),
              if (profile?.contractorName != null &&
                  profile!.contractorName!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Prepared by: ${profile.contractorName}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (contactLine.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(contactLine, style: AppTextStyles.body),
              ],
              if (license != null && license.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text('License #$license', style: AppTextStyles.caption),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        // Right: date
        Text(
          Formatters.date(estimate.createdAt),
          style: AppTextStyles.caption,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Client block
  // --------------------------------------------------------------------------

  Widget _buildClientBlock(Estimate estimate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PREPARED FOR:', style: AppTextStyles.sectionLabel),
        const SizedBox(height: AppSpacing.sm),
        Text(estimate.clientName ?? '—', style: AppTextStyles.heading2),
        if (estimate.clientEmail != null && estimate.clientEmail!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(estimate.clientEmail!, style: AppTextStyles.body),
        ],
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Estimate body (scope of work)
  // --------------------------------------------------------------------------

  Widget _buildEstimateBody(Estimate estimate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('SCOPE OF WORK', style: AppTextStyles.sectionLabel),
            ),
            _buildStatusBadge(estimate.status),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_isEditMode)
          TextField(
            controller: _bodyController,
            autofocus: true,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: AppTextStyles.body.copyWith(height: AppSpacing.previewBodyLineHeight),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide: const BorderSide(color: AppColors.borderDefault),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide: const BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide: const BorderSide(
                  color: AppColors.borderActive,
                  width: AppSpacing.focusedBorderWidth,
                ),
              ),
              contentPadding: const EdgeInsets.all(AppSpacing.md),
            ),
          )
        else
          Text(
            estimate.aiGeneratedBody ?? 'No estimate body generated.',
            style: AppTextStyles.body.copyWith(height: AppSpacing.previewBodyLineHeight),
          ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Status badge
  // --------------------------------------------------------------------------

  Widget _buildStatusBadge(String status) {
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

  // --------------------------------------------------------------------------
  // Cost summary
  // --------------------------------------------------------------------------

  Widget _buildCostSummary(Estimate estimate) {
    final laborCost = (estimate.laborHours ?? 0) * (estimate.laborRate ?? 0);
    final materials = estimate.materialsCost ?? 0;
    final additional = estimate.additionalFees ?? 0;
    final total = estimate.totalEstimate ?? estimate.computedTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('COST SUMMARY', style: AppTextStyles.sectionLabel),
        const SizedBox(height: AppSpacing.md),
        // Labor row
        _buildCostRow(
          label: 'Labor',
          amount: laborCost,
          detail: _laborDetail(estimate.laborHours, estimate.laborRate),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Materials row
        _buildCostRow(label: 'Materials', amount: materials),
        const SizedBox(height: AppSpacing.sm),
        // Additional fees row
        _buildCostRow(label: 'Additional Fees', amount: additional),
        const SizedBox(height: AppSpacing.md),
        // Divider before total
        const Divider(
          color: AppColors.divider,
          thickness: AppSpacing.costSummaryDividerThickness,
        ),
        const SizedBox(height: AppSpacing.sm),
        // Total row
        Row(
          children: [
            Text(
              'TOTAL',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              Formatters.currency(total),
              style: AppTextStyles.totalAmount,
            ),
          ],
        ),
      ],
    );
  }

  String? _laborDetail(double? hours, double? rate) {
    if (hours == null || rate == null) return null;
    final h = hours % 1 == 0 ? hours.toInt().toString() : hours.toStringAsFixed(1);
    final r = Formatters.currency(rate);
    return '($h hrs x $r/hr)';
  }

  Widget _buildCostRow({
    required String label,
    required double amount,
    String? detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.body),
              if (detail != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(detail, style: AppTextStyles.caption),
              ],
            ],
          ),
        ),
        Text(
          Formatters.currency(amount),
          style: AppTextStyles.body,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Terms
  // --------------------------------------------------------------------------

  Widget _buildTerms() {
    final businessName = _profile?.companyName ??
        _profile?.fullName ??
        'Your Business';

    final terms = AppStrings.standardTradeTerms.replaceAll('[Business Name]', businessName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TERMS & CONDITIONS', style: AppTextStyles.sectionLabel),
        const SizedBox(height: AppSpacing.sm),
        Text(
          terms,
          style: AppTextStyles.caption.copyWith(height: AppSpacing.previewTermsLineHeight),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Divider
  // --------------------------------------------------------------------------

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Divider(
        color: AppColors.divider,
        thickness: AppSpacing.costSummaryDividerThickness,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Bottom action bar
  // --------------------------------------------------------------------------

  Widget _buildBottomBar(bool anyLoading) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSpacing.buttonHeight,
          child: Row(
            children: [
              // Download PDF button
              Expanded(
                child: _ActionButton(
                  label: 'Download PDF',
                  isLoading: _isPdfLoading,
                  enabled: !anyLoading,
                  backgroundColor: AppColors.surfaceElevated,
                  textColor: AppColors.textPrimary,
                  onTap: _handleDownloadPdf,
                  borderRadius: BorderRadius.zero,
                ),
              ),
              // Divider between buttons
              const SizedBox(
                width: AppSpacing.tileBorderWidth,
                height: AppSpacing.buttonHeight,
                child: ColoredBox(color: AppColors.divider),
              ),
              // Email to Client button
              Expanded(
                child: _ActionButton(
                  label: 'Email to Client',
                  isLoading: _isEmailLoading,
                  enabled: !anyLoading,
                  backgroundColor: AppColors.positive,
                  textColor: AppColors.background,
                  onTap: _handleEmailToClient,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private action button widget
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool enabled;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  const _ActionButton({
    required this.label,
    required this.isLoading,
    required this.enabled,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? backgroundColor : backgroundColor.withValues(alpha: 0.5),
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: enabled ? onTap : null,
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: AppSpacing.xl,
                  height: AppSpacing.xl,
                  child: CircularProgressIndicator(
                    strokeWidth: AppSpacing.progressStrokeWidth,
                    valueColor: AlwaysStoppedAnimation<Color>(textColor),
                  ),
                )
              : Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    color: enabled ? textColor : textColor.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

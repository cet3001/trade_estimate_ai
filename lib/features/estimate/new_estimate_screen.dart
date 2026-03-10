import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/trade_templates.dart';
import '../../core/models/entitlements.dart';
import '../../core/models/estimate.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/loading_overlay.dart';
import '../paywall/paywall_screen.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class NewEstimateScreen extends StatefulWidget {
  const NewEstimateScreen({super.key, this.prefillEstimate});

  /// When provided, the form fields are pre-filled from this estimate so the
  /// user can review and edit the data before regenerating.
  final Estimate? prefillEstimate;

  @override
  State<NewEstimateScreen> createState() => _NewEstimateScreenState();
}

class _NewEstimateScreenState extends State<NewEstimateScreen> {
  // -- Step state
  int _step = 0; // 0..3
  late final PageController _pageController;

  // -- Trade selection
  TradeType? _selectedTrade;

  // -- Form keys (one per step so we can validate independently)
  final _formKeyStep2 = GlobalKey<FormBuilderState>();
  final _formKeyStep3 = GlobalKey<FormBuilderState>();

  // -- Accumulated values (populated on step advance)
  String _clientName = '';
  String _clientEmail = '';
  String _jobTitle = '';
  String _jobLocation = '';
  String _jobDescription = '';
  Map<String, dynamic> _scopeDetails = {};

  double _laborHours = 0;
  double _laborRate = 0;
  double _materialsCost = 0;
  double _additionalFees = 0;
  String _notes = '';
  bool _saveLaborRate = false;

  // -- Live cost summary state (updated by step-3 field changes)
  double _liveLaborHours = 0;
  double _liveLaborRate = 0;
  double _liveMaterialsCost = 0;
  double _liveAdditionalFees = 0;

  // -- Profile / entitlements
  UserProfile? _profile;
  Entitlements _entitlements = Entitlements.empty;

  // -- Loading overlay
  bool _isGenerating = false;
  String? _generationError;

  final _service = SupabaseService();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _applyPrefill();
    _pageController = PageController(initialPage: _step);
    _loadProfile();
  }

  void _applyPrefill() {
    final prefill = widget.prefillEstimate;
    if (prefill == null) return;
    _selectedTrade = prefill.trade;
    _clientName = prefill.clientName ?? '';
    _clientEmail = prefill.clientEmail ?? '';
    _jobTitle = prefill.jobTitle ?? '';
    _jobLocation = prefill.jobLocation ?? '';
    _jobDescription = prefill.jobDescription ?? '';
    _scopeDetails = prefill.scopeDetails ?? {};
    _laborHours = prefill.laborHours ?? 0;
    _laborRate = prefill.laborRate ?? 0;
    _materialsCost = prefill.materialsCost ?? 0;
    _additionalFees = prefill.additionalFees ?? 0;
    _notes = prefill.notes ?? '';
    _liveLaborHours = prefill.laborHours ?? 0;
    _liveLaborRate = prefill.laborRate ?? 0;
    _liveMaterialsCost = prefill.materialsCost ?? 0;
    _liveAdditionalFees = prefill.additionalFees ?? 0;
    // Skip to step 1 (job details) so the user can review and edit.
    _step = 1;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await _service.getProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _entitlements = profile != null
          ? Entitlements.fromUserProfile(profile)
          : Entitlements.empty;
      // Pre-seed live rate with saved default only when no prefill was provided
      if (widget.prefillEstimate == null && profile?.defaultLaborRate != null) {
        _liveLaborRate = profile!.defaultLaborRate!;
        _laborRate = profile.defaultLaborRate!;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _goBack() {
    if (_step == 0 || (_step == 1 && widget.prefillEstimate != null)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step--);
    _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _advanceTo(int next) {
    setState(() => _step = next);
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1: Trade selected
  // ---------------------------------------------------------------------------

  void _onTradeSelected(TradeType trade) {
    setState(() => _selectedTrade = trade);
    // Give 150 ms of visual feedback then advance
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _advanceTo(1);
    });
  }

  // ---------------------------------------------------------------------------
  // Step 2: Validate & advance
  // ---------------------------------------------------------------------------

  void _onStep2Next() {
    if (_formKeyStep2.currentState?.saveAndValidate() ?? false) {
      final values = _formKeyStep2.currentState!.value;
      _clientName = (values['client_name'] as String?) ?? '';
      _clientEmail = (values['client_email'] as String?) ?? '';
      _jobTitle = (values['job_title'] as String?) ?? '';
      _jobLocation = (values['job_location'] as String?) ?? '';
      _jobDescription = (values['job_description'] as String?) ?? '';
      // Collect all remaining keys as scope details
      _scopeDetails = {};
      for (final key in values.keys) {
        if (!['client_name', 'client_email', 'job_title', 'job_location',
              'job_description'].contains(key)) {
          _scopeDetails[key] = values[key];
        }
      }
      _advanceTo(2);
    }
  }

  // ---------------------------------------------------------------------------
  // Step 3: Validate & advance
  // ---------------------------------------------------------------------------

  Future<void> _onStep3Next() async {
    if (!(_formKeyStep3.currentState?.saveAndValidate() ?? false)) return;
    final values = _formKeyStep3.currentState!.value;
    _laborHours = double.tryParse((values['labor_hours'] as String?) ?? '') ?? 0;
    _laborRate = double.tryParse((values['labor_rate'] as String?) ?? '') ?? 0;
    _materialsCost = double.tryParse((values['materials_cost'] as String?) ?? '') ?? 0;
    _additionalFees = double.tryParse((values['additional_fees'] as String?) ?? '') ?? 0;
    _notes = (values['notes'] as String?) ?? '';
    _saveLaborRate = (values['save_labor_rate'] as bool?) ?? false;

    if (_saveLaborRate && _laborRate > 0) {
      await _service.updateProfile({'default_labor_rate': _laborRate});
    }
    if (!mounted) return;
    _advanceTo(3);
  }

  // ---------------------------------------------------------------------------
  // Step 4: Generate estimate
  // ---------------------------------------------------------------------------

  Future<void> _onGenerate() async {
    if (!_entitlements.canGenerateEstimate) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PaywallScreen(onSuccess: _loadProfile),
        ),
      );
      if (!mounted) return;
      await _loadProfile();   // re-fetch fresh entitlements after paywall closes
      if (!mounted) return;
      if (!_entitlements.canGenerateEstimate) return;
    }

    setState(() {
      _isGenerating = true;
      _generationError = null;
    });

    try {
      final trade = _selectedTrade ?? TradeType.plumbing;

      final body = {
        'trade': trade.value,
        'jobTitle': _jobTitle,
        'jobDescription': _jobDescription,
        'scopeDetails': _scopeDetails,
        'laborHours': _laborHours,
        'laborRate': _laborRate,
        'materialsCost': _materialsCost,
        'additionalFees': _additionalFees,
        'clientName': _clientName,
        'clientEmail': _clientEmail,
        'jobLocation': _jobLocation,
        'notes': _notes,
        'businessName': _profile?.companyName ?? '',
        'licenseNumber': _profile?.licenseNumber ?? '',
      };

      final estimate = await _service.generateEstimate(body);

      if (!mounted) return;

      setState(() => _isGenerating = false);

      Navigator.of(context).pushReplacementNamed(
        '/estimate/preview',
        arguments: estimate,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _generationError = 'Something went wrong. Please try again.';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Input decoration helper
  // ---------------------------------------------------------------------------

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.surfaceElevated,
      labelStyle: AppTextStyles.label,
      hintStyle: AppTextStyles.caption,
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
            color: AppColors.borderActive, width: AppSpacing.focusedBorderWidth),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.md),
        borderSide: const BorderSide(color: AppColors.negative),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.md),
        borderSide: const BorderSide(
            color: AppColors.negative, width: AppSpacing.focusedBorderWidth),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Computed totals
  // ---------------------------------------------------------------------------

  double get _liveTotal =>
      (_liveLaborHours * _liveLaborRate) + _liveMaterialsCost + _liveAdditionalFees;

  double get _confirmTotal =>
      (_laborHours * _laborRate) + _materialsCost + _additionalFees;

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isGenerating,
      message: 'Writing your estimate...',
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildStepIndicator(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStep1(),
                    _buildStep2(),
                    _buildStep3(),
                    _buildStep4(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header (back button + close)
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (_step > 0)
            Material(
              color: AppColors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.md),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _isGenerating ? null : _goBack,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Icon(
                    Icons.chevron_left,
                    color: AppColors.textPrimary,
                    size: AppSpacing.xxl,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: AppSpacing.xxl + AppSpacing.sm * 2),
          Expanded(
            child: Center(
              child: Text(
                _stepTitle(),
                style: AppTextStyles.heading2,
              ),
            ),
          ),
          Material(
            color: AppColors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _isGenerating ? null : () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Icon(
                  Icons.close,
                  color: AppColors.textSecondary,
                  size: AppSpacing.xl,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stepTitle() {
    switch (_step) {
      case 0:
        return 'Select Trade';
      case 1:
        return 'Job Details';
      case 2:
        return 'Cost Breakdown';
      case 3:
        return 'Review & Generate';
      default:
        return '';
    }
  }

  // ---------------------------------------------------------------------------
  // Step indicator (4 dots)
  // ---------------------------------------------------------------------------

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final isActive = i == _step;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            width: isActive
                ? AppSpacing.stepIndicatorDotActiveSize
                : AppSpacing.stepIndicatorDotSize,
            height: isActive
                ? AppSpacing.stepIndicatorDotActiveSize
                : AppSpacing.stepIndicatorDotSize,
            decoration: BoxDecoration(
              color: i <= _step ? AppColors.positive : AppColors.surfaceElevated,
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 1: Trade Selector
  // ---------------------------------------------------------------------------

  Widget _buildStep1() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.lg,
          crossAxisSpacing: AppSpacing.lg,
          childAspectRatio: 1,
          children: TradeTemplates.all.map((info) {
            return _TradeTile(
              info: info,
              isSelected: _selectedTrade == info.type,
              onTap: () => _onTradeSelected(info.type),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 2: Job Details
  // ---------------------------------------------------------------------------

  Widget _buildStep2() {
    if (_selectedTrade == null) return const SizedBox.shrink();
    return FormBuilder(
      key: _formKeyStep2,
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        children: [
          // Common fields
          _buildSectionLabel('Client Info'),
          const SizedBox(height: AppSpacing.sm),
          FormBuilderTextField(
            name: 'client_name',
            initialValue: _clientName.isNotEmpty ? _clientName : null,
            decoration: _fieldDecoration('Client Name'),
            textInputAction: TextInputAction.next,
            validator: FormBuilderValidators.required(
                errorText: 'Client name is required'),
          ),
          const SizedBox(height: AppSpacing.md),
          FormBuilderTextField(
            name: 'client_email',
            initialValue: _clientEmail.isNotEmpty ? _clientEmail : null,
            decoration: _fieldDecoration('Client Email'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: FormBuilderValidators.compose([
              FormBuilderValidators.required(
                  errorText: 'Client email is required'),
              FormBuilderValidators.email(errorText: 'Enter a valid email'),
            ]),
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSectionLabel('Job Info'),
          const SizedBox(height: AppSpacing.sm),
          FormBuilderTextField(
            name: 'job_title',
            initialValue: _jobTitle.isNotEmpty ? _jobTitle : null,
            decoration: _fieldDecoration('Job Title',
                hint: _jobTitleHint()),
            textInputAction: TextInputAction.next,
            validator: FormBuilderValidators.required(
                errorText: 'Job title is required'),
          ),
          const SizedBox(height: AppSpacing.md),
          FormBuilderTextField(
            name: 'job_location',
            initialValue: _jobLocation.isNotEmpty ? _jobLocation : null,
            decoration: _fieldDecoration('Job Location / Address',
                hint: '123 Main St, City, State'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Trade-specific fields
          _buildSectionLabel('${_selectedTrade!.displayName} Details'),
          const SizedBox(height: AppSpacing.sm),
          ..._buildTradeFields(),

          const SizedBox(height: AppSpacing.xl),
          _buildNextButton(_onStep2Next),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  String _jobTitleHint() {
    switch (_selectedTrade) {
      case TradeType.plumbing:
        return 'Master Bathroom Remodel';
      case TradeType.electrical:
        return 'Panel Upgrade to 200A';
      case TradeType.roofing:
        return 'Full Roof Replacement';
      case TradeType.construction:
        return 'Kitchen Addition';
      default:
        return 'Job Title';
    }
  }

  List<Widget> _buildTradeFields() {
    switch (_selectedTrade) {
      case TradeType.plumbing:
        return _plumbingFields();
      case TradeType.electrical:
        return _electricalFields();
      case TradeType.roofing:
        return _roofingFields();
      case TradeType.construction:
        return _constructionFields();
      default:
        return [];
    }
  }

  List<Widget> _plumbingFields() {
    return [
      FormBuilderTextField(
        name: 'job_description',
        initialValue: _jobDescription.isNotEmpty ? _jobDescription : null,
        decoration: _fieldDecoration('Describe the plumbing work needed'),
        maxLines: 4,
        validator: FormBuilderValidators.required(
            errorText: 'Description is required'),
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderDropdown<String>(
        name: 'work_type',
        decoration: _fieldDecoration('Type of Work'),
        items: TradeTemplates.workTypes[TradeType.plumbing]!
            .map((s) => DropdownMenuItem(value: s, child: Text(s, style: AppTextStyles.body)))
            .toList(),
        validator: FormBuilderValidators.required(
            errorText: 'Please select a work type'),
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderTextField(
        name: 'fixture_count',
        decoration: _fieldDecoration('Number of Fixtures Involved', hint: 'e.g. 3'),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      const SizedBox(height: AppSpacing.md),
      _buildSwitchRow('home_over_30_years', 'Home older than 30 years?'),
    ];
  }

  List<Widget> _electricalFields() {
    return [
      FormBuilderTextField(
        name: 'job_description',
        initialValue: _jobDescription.isNotEmpty ? _jobDescription : null,
        decoration: _fieldDecoration('Describe the electrical work needed'),
        maxLines: 4,
        validator: FormBuilderValidators.required(
            errorText: 'Description is required'),
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderDropdown<String>(
        name: 'work_type',
        decoration: _fieldDecoration('Type of Work'),
        items: TradeTemplates.workTypes[TradeType.electrical]!
            .map((s) => DropdownMenuItem(value: s, child: Text(s, style: AppTextStyles.body)))
            .toList(),
        validator: FormBuilderValidators.required(
            errorText: 'Please select a work type'),
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderTextField(
        name: 'amp_service_size',
        decoration:
            _fieldDecoration('Amp Service Size (if known)', hint: 'e.g. 200A'),
        keyboardType: TextInputType.text,
      ),
      const SizedBox(height: AppSpacing.md),
      _buildSwitchRow('permits_required', 'Permits required?'),
    ];
  }

  List<Widget> _roofingFields() {
    return [
      FormBuilderTextField(
        name: 'job_description',
        initialValue: _jobDescription.isNotEmpty ? _jobDescription : null,
        decoration: _fieldDecoration('Describe the roofing work needed'),
        maxLines: 4,
        validator: FormBuilderValidators.required(
            errorText: 'Description is required'),
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderDropdown<String>(
        name: 'work_type',
        decoration: _fieldDecoration('Type of Work'),
        items: TradeTemplates.workTypes[TradeType.roofing]!
            .map((s) => DropdownMenuItem(value: s, child: Text(s, style: AppTextStyles.body)))
            .toList(),
        validator: FormBuilderValidators.required(
            errorText: 'Please select a work type'),
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderTextField(
        name: 'square_footage',
        decoration: _fieldDecoration('Approximate Square Footage', hint: 'e.g. 2400'),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderDropdown<String>(
        name: 'existing_material',
        decoration: _fieldDecoration('Existing Roof Material'),
        items: ['Asphalt Shingle', 'Metal', 'Tile', 'Flat', 'Unknown']
            .map((s) => DropdownMenuItem(value: s, child: Text(s, style: AppTextStyles.body)))
            .toList(),
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderDropdown<String>(
        name: 'stories',
        decoration: _fieldDecoration('Stories'),
        items: ['1', '2', '3+']
            .map((s) => DropdownMenuItem(value: s, child: Text(s, style: AppTextStyles.body)))
            .toList(),
        validator: FormBuilderValidators.required(
            errorText: 'Please select the number of stories'),
      ),
    ];
  }

  List<Widget> _constructionFields() {
    return [
      FormBuilderTextField(
        name: 'job_description',
        initialValue: _jobDescription.isNotEmpty ? _jobDescription : null,
        decoration: _fieldDecoration('Describe the construction work needed'),
        maxLines: 4,
        validator: FormBuilderValidators.required(
            errorText: 'Description is required'),
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderDropdown<String>(
        name: 'work_type',
        decoration: _fieldDecoration('Project Type'),
        items: TradeTemplates.workTypes[TradeType.construction]!
            .map((s) => DropdownMenuItem(value: s, child: Text(s, style: AppTextStyles.body)))
            .toList(),
        validator: FormBuilderValidators.required(
            errorText: 'Please select a project type'),
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderTextField(
        name: 'square_footage',
        decoration: _fieldDecoration('Approximate Square Footage', hint: 'e.g. 1200'),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      const SizedBox(height: AppSpacing.md),
      FormBuilderTextField(
        name: 'timeline',
        decoration: _fieldDecoration('Timeline Expectation', hint: '2 weeks, ASAP'),
      ),
    ];
  }

  Widget _buildSwitchRow(String name, String label) {
    return FormBuilderSwitch(
      name: name,
      title: Text(label, style: AppTextStyles.body),
      initialValue: false,
      activeColor: AppColors.positive,
      decoration: const InputDecoration(border: InputBorder.none),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(text, style: AppTextStyles.sectionLabel);
  }

  // ---------------------------------------------------------------------------
  // STEP 3: Cost Breakdown
  // ---------------------------------------------------------------------------

  Widget _buildStep3() {
    final defaultRate = _profile?.defaultLaborRate;
    return FormBuilder(
      key: _formKeyStep3,
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        children: [
          _buildSectionLabel('Labor'),
          const SizedBox(height: AppSpacing.sm),
          FormBuilderTextField(
            name: 'labor_hours',
            initialValue: _laborHours > 0 ? _laborHours.toString() : null,
            decoration: _fieldDecoration('Labor Hours', hint: 'e.g. 20'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (val) => setState(() {
              _liveLaborHours = double.tryParse(val ?? '') ?? 0;
            }),
            validator: FormBuilderValidators.compose([
              FormBuilderValidators.required(errorText: 'Labor hours required'),
              FormBuilderValidators.numeric(errorText: 'Enter a number'),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          FormBuilderTextField(
            name: 'labor_rate',
            initialValue: (widget.prefillEstimate != null && _laborRate > 0)
                ? _laborRate.toString()
                : (defaultRate != null
                    ? defaultRate.toString()
                    : (_laborRate > 0 ? _laborRate.toString() : null)),
            decoration: _fieldDecoration('Labor Rate (per hour)', hint: 'e.g. 85'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (val) => setState(() {
              _liveLaborRate = double.tryParse(val ?? '') ?? 0;
            }),
            validator: FormBuilderValidators.compose([
              FormBuilderValidators.required(errorText: 'Labor rate required'),
              FormBuilderValidators.numeric(errorText: 'Enter a number'),
            ]),
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSectionLabel('Costs'),
          const SizedBox(height: AppSpacing.sm),
          FormBuilderTextField(
            name: 'materials_cost',
            initialValue: _materialsCost > 0 ? _materialsCost.toString() : null,
            decoration: _fieldDecoration('Materials Cost (\$)', hint: 'e.g. 2500'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (val) => setState(() {
              _liveMaterialsCost = double.tryParse(val ?? '') ?? 0;
            }),
            validator: FormBuilderValidators.compose([
              FormBuilderValidators.required(
                  errorText: 'Materials cost required'),
              FormBuilderValidators.numeric(errorText: 'Enter a number'),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          FormBuilderTextField(
            name: 'additional_fees',
            initialValue: _additionalFees > 0 ? _additionalFees.toString() : null,
            decoration: _fieldDecoration('Additional Fees (\$)',
                hint: 'Permit fees, disposal, equipment rental'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (val) => setState(() {
              _liveAdditionalFees = double.tryParse(val ?? '') ?? 0;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          FormBuilderTextField(
            name: 'notes',
            initialValue: _notes.isNotEmpty ? _notes : null,
            decoration: _fieldDecoration('Notes / Exclusions',
                hint: 'Does not include drywall repair'),
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Live cost summary
          _buildLiveCostSummary(),
          const SizedBox(height: AppSpacing.xl),

          // Save labor rate toggle
          FormBuilderSwitch(
            name: 'save_labor_rate',
            title: Text('Save my labor rate', style: AppTextStyles.body),
            subtitle: Text(
              'Use as default for future estimates',
              style: AppTextStyles.caption,
            ),
            initialValue: false,
            activeColor: AppColors.positive,
            decoration: const InputDecoration(border: InputBorder.none),
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildNextButton(_onStep3Next),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _buildLiveCostSummary() {
    final laborCost = _liveLaborHours * _liveLaborRate;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Summary', style: AppTextStyles.sectionLabel),
          const SizedBox(height: AppSpacing.md),
          _summaryRow(
            'Labor',
            Formatters.currency(laborCost),
            detail: '${_liveLaborHours.toStringAsFixed(0)} hrs × ${Formatters.currency(_liveLaborRate)}/hr',
          ),
          const SizedBox(height: AppSpacing.sm),
          _summaryRow('Materials', Formatters.currency(_liveMaterialsCost)),
          const SizedBox(height: AppSpacing.sm),
          _summaryRow('Additional', Formatters.currency(_liveAdditionalFees)),
          const SizedBox(height: AppSpacing.md),
          Container(
            height: AppSpacing.costSummaryDividerThickness,
            color: AppColors.divider,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: AppTextStyles.heading2),
              Text(
                Formatters.currency(_liveTotal),
                style: AppTextStyles.totalAmount,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String amount, {String? detail}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.body),
              if (detail != null)
                Text(detail, style: AppTextStyles.caption),
            ],
          ),
        ),
        Text(amount, style: AppTextStyles.body),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 4: Review & Generate
  // ---------------------------------------------------------------------------

  Widget _buildStep4() {
    final trade = _selectedTrade ?? TradeType.plumbing;
    final info = TradeTemplates.byType(trade);
    final labor = _laborHours * _laborRate;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      children: [
        // Trade badge
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.md),
            border: Border.all(color: info.color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: AppSpacing.tradeIconBadgeSize,
                height: AppSpacing.tradeIconBadgeSize,
                decoration: BoxDecoration(
                  color: info.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.sm),
                ),
                child: Center(
                  child: Text(
                    info.emoji,
                    style: const TextStyle(fontSize: AppSpacing.xl),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.label, style: AppTextStyles.heading2.copyWith(color: info.color)),
                  Text(
                    'Claude will write a professional ${info.label} estimate\nbased on your job details.',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Client + job summary
        _buildReviewCard(
          title: 'Client & Job',
          rows: [
            _ReviewRow(label: 'Client', value: _clientName),
            _ReviewRow(label: 'Email', value: _clientEmail),
            _ReviewRow(label: 'Job', value: _jobTitle),
            if (_jobLocation.isNotEmpty)
              _ReviewRow(label: 'Location', value: _jobLocation),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Cost summary
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.md),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cost Breakdown', style: AppTextStyles.sectionLabel),
              const SizedBox(height: AppSpacing.md),
              _summaryRow(
                'Labor',
                Formatters.currency(labor),
                detail:
                    '${_laborHours.toStringAsFixed(0)} hrs × ${Formatters.currency(_laborRate)}/hr',
              ),
              const SizedBox(height: AppSpacing.sm),
              _summaryRow('Materials', Formatters.currency(_materialsCost)),
              const SizedBox(height: AppSpacing.sm),
              _summaryRow('Additional', Formatters.currency(_additionalFees)),
              const SizedBox(height: AppSpacing.md),
              Container(
                height: AppSpacing.costSummaryDividerThickness,
                color: AppColors.divider,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: AppTextStyles.heading2),
                  Text(
                    Formatters.currency(_confirmTotal),
                    style: AppTextStyles.totalAmount,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Error message
        if (_generationError != null) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.negative.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.md),
              border: Border.all(color: AppColors.negative.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.negative, size: AppSpacing.xl),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(_generationError!, style: AppTextStyles.body.copyWith(color: AppColors.negative)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // Generate button
        _ScaleButton(
          onTap: _isGenerating ? null : _onGenerate,
          child: Container(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            decoration: BoxDecoration(
              color: AppColors.positive,
              borderRadius: BorderRadius.circular(AppSpacing.md),
            ),
            child: Center(
              child: Text(
                _generationError != null ? 'Try Again' : 'Generate Estimate',
                style: AppTextStyles.heading2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _buildReviewCard({
    required String title,
    required List<_ReviewRow> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.sectionLabel),
          const SizedBox(height: AppSpacing.md),
          ...rows.map((row) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AppSpacing.huge + AppSpacing.md,
                  child: Text(row.label, style: AppTextStyles.caption),
                ),
                Expanded(
                  child: Text(row.value, style: AppTextStyles.body),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared Next button
  // ---------------------------------------------------------------------------

  Widget _buildNextButton(VoidCallback? onTap) {
    return _ScaleButton(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: AppSpacing.buttonHeight,
        decoration: BoxDecoration(
          color: AppColors.positive,
          borderRadius: BorderRadius.circular(AppSpacing.md),
        ),
        child: Center(
          child: Text(
            'Next',
            style: AppTextStyles.heading2.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trade Tile widget (Step 1)
// ---------------------------------------------------------------------------

class _TradeTile extends StatefulWidget {
  final TradeInfo info;
  final bool isSelected;
  final VoidCallback onTap;

  const _TradeTile({
    required this.info,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TradeTile> createState() => _TradeTileState();
}

class _TradeTileState extends State<_TradeTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 0.0,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (context, child) =>
          Transform.scale(scale: _scaleAnim.value, child: child),
      child: SizedBox(
        width: AppSpacing.tradeTileSize,
        height: AppSpacing.tradeTileSize,
        child: Material(
          color: AppColors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.tradeTileBorderRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTapDown: (_) => _scaleController.forward(),
            onTapUp: (_) {
              _scaleController.reverse();
              widget.onTap();
            },
            onTapCancel: () => _scaleController.reverse(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? widget.info.color.withValues(alpha: 0.12)
                    : AppColors.surface,
                borderRadius:
                    BorderRadius.circular(AppSpacing.tradeTileBorderRadius),
                border: Border.all(
                  color: widget.isSelected
                      ? AppColors.borderActive
                      : AppColors.borderDefault,
                  width: widget.isSelected
                      ? AppSpacing.cardAccentBorderWidth
                      : AppSpacing.tileBorderWidth,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.info.emoji,
                          style: const TextStyle(
                              fontSize: AppSpacing.tradeTileEmojiSize),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          widget.info.label,
                          style: AppTextStyles.heading2.copyWith(
                            color: widget.isSelected
                                ? widget.info.color
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isSelected)
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Container(
                        width: AppSpacing.tradeTileCheckSize,
                        height: AppSpacing.tradeTileCheckSize,
                        decoration: const BoxDecoration(
                          color: AppColors.positive,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: AppColors.textPrimary,
                          size: AppSpacing.tradeTileCheckIconSize,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scale button with press animation (used for Next / Generate)
// ---------------------------------------------------------------------------

class _ScaleButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _ScaleButton({required this.onTap, required this.child});

  @override
  State<_ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<_ScaleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 0.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: Material(
        color: AppColors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTapDown: widget.onTap != null ? (_) => _ctrl.forward() : null,
          onTapUp: widget.onTap != null
              ? (_) {
                  _ctrl.reverse();
                  widget.onTap!();
                }
              : null,
          onTapCancel: () => _ctrl.reverse(),
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Simple data class for review card rows
// ---------------------------------------------------------------------------

class _ReviewRow {
  final String label;
  final String value;

  const _ReviewRow({required this.label, required this.value});
}

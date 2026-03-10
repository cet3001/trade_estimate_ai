import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../constants/app_strings.dart';
import '../models/estimate.dart';
import '../models/user_profile.dart';

// ---------------------------------------------------------------------------
// PDF colour constants (matching app tokens, in PDF RGB space)
// ---------------------------------------------------------------------------

const _colorPositive = PdfColor.fromInt(0xFF34C759);   // AppColors.positive
const _colorSecondary = PdfColor.fromInt(0xFF8E8E93);  // AppColors.textSecondary
const _colorText = PdfColor.fromInt(0xFF000000);       // black body text
const _colorDivider = PdfColor.fromInt(0xFFDDDDDD);    // light divider for print

// ---------------------------------------------------------------------------
// PdfService
// ---------------------------------------------------------------------------

class PdfService {
  PdfService._();

  // --------------------------------------------------------------------------
  // PDF Layout Constants
  // --------------------------------------------------------------------------

  // Page
  static const double _pageMargin = 36.0;          // 0.5 inch margin

  // Font sizes
  static const double _businessNameFontSize = 14.0;
  static const double _estimateTitleFontSize = 16.0;
  static const double _clientNameFontSize = 12.0;
  static const double _sectionLabelFontSize = 10.0;
  static const double _bodyFontSize = 11.0;
  static const double _subBodyFontSize = 10.0;
  static const double _captionFontSize = 9.0;
  static const double _smallFontSize = 8.0;
  static const double _totalLabelFontSize = 13.0;
  static const double _totalAmountFontSize = 14.0;
  static const double _idFontSize = 9.0;
  static const double _termsFontSize = 8.0;
  static const double _termsLabelFontSize = 9.0;

  // Letter spacing
  static const double _sectionLabelSpacing = 0.8;

  // Spacing / gaps
  static const double _headerAfterInfoGap = 8.0;
  static const double _headerAfterDividerGap = 6.0;
  static const double _footerBeforeTextGap = 4.0;
  static const double _clientNameGap = 4.0;
  static const double _afterClientBlockGap = 8.0;
  static const double _afterDividerSmallGap = 8.0;
  static const double _sectionLabelGap = 6.0;
  static const double _afterBodyTextGap = 12.0;
  static const double _costSectionLabelGap = 8.0;
  static const double _itemSpacing = 4.0;
  static const double _afterCostTableGap = 8.0;
  static const double _afterTotalDividerGap = 6.0;
  static const double _afterTotalGap = 12.0;
  static const double _afterTermsDividerGap = 8.0;
  static const double _termsLabelGap = 4.0;

  // Body line spacing
  static const double _bodyLineSpacing = 4.0;
  static const double _termsLineSpacing = 2.0;

  // Divider thickness
  static const double _dividerThickness = 1.0;

  // Column widths for cost table
  static const double _costLabelColumnFlex = 3.0;
  static const double _costAmountColumnFlex = 1.0;

  /// Generate a letter-size PDF for [estimate] + [profile] and return the
  /// [File] saved to the app's temporary directory.
  static Future<File> generatePdf(Estimate estimate, UserProfile profile) async {
    final doc = pw.Document();

    // ---- Fonts (standard PDF fonts — no embedding required)
    final fontHelvetica = pw.Font.helvetica();
    final fontHelveticaBold = pw.Font.helveticaBold();
    final fontCourier = pw.Font.courier();
    final fontCourierBold = pw.Font.courierBold();

    // ---- Helpers
    final businessName =
        profile.companyName ?? profile.fullName ?? 'Your Business';
    final dateFormatter = DateFormat('MMMM d, yyyy');
    final currencyFormatter = NumberFormat.currency(
      locale: 'en_US',
      symbol: r'$',
      decimalDigits: 2,
    );

    String fmtCurrency(double? value) =>
        currencyFormatter.format(value ?? 0.0);

    final laborCost = (estimate.laborHours ?? 0) * (estimate.laborRate ?? 0);
    final materialsCost = estimate.materialsCost ?? 0;
    final additionalFees = estimate.additionalFees ?? 0;
    final total = estimate.totalEstimate ??
        (laborCost + materialsCost + additionalFees);

    final laborDetailText = () {
      final h = estimate.laborHours;
      final r = estimate.laborRate;
      if (h == null || r == null) return '';
      final hStr =
          h % 1 == 0 ? h.toInt().toString() : h.toStringAsFixed(1);
      return '($hStr hrs × ${fmtCurrency(r)}/hr)';
    }();

    final terms = AppStrings.standardTradeTerms.replaceAll('[Business Name]', businessName);

    // ---- Styles
    pw.TextStyle body(double size, {bool bold = false, PdfColor? color}) {
      return pw.TextStyle(
        font: bold ? fontHelveticaBold : fontHelvetica,
        fontSize: size,
        color: color ?? _colorText,
      );
    }

    pw.TextStyle mono(double size, {bool bold = false, PdfColor? color}) {
      return pw.TextStyle(
        font: bold ? fontCourierBold : fontCourier,
        fontSize: size,
        color: color ?? _colorText,
      );
    }

    // ---- Build page
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(_pageMargin),
        // ---- Page header
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left: business info
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(businessName, style: body(_businessNameFontSize, bold: true)),
                      if (profile.phone != null && profile.phone!.isNotEmpty)
                        pw.Text(profile.phone!, style: body(_subBodyFontSize, color: _colorSecondary)),
                      if (profile.email != null && profile.email!.isNotEmpty)
                        pw.Text(profile.email!, style: body(_subBodyFontSize, color: _colorSecondary)),
                      if (profile.licenseNumber != null &&
                          profile.licenseNumber!.isNotEmpty)
                        pw.Text(
                          'License #${profile.licenseNumber}',
                          style: body(_subBodyFontSize, color: _colorSecondary),
                        ),
                    ],
                  ),
                ),
                // Right: ESTIMATE title + date + ID
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'ESTIMATE',
                      style: pw.TextStyle(
                        font: fontHelveticaBold,
                        fontSize: _estimateTitleFontSize,
                        color: _colorPositive,
                      ),
                    ),
                    pw.Text(
                      dateFormatter.format(estimate.createdAt),
                      style: body(_subBodyFontSize),
                    ),
                    pw.Text(
                      estimate.id.length > 12
                          ? estimate.id.substring(0, 12)
                          : estimate.id,
                      style: body(_idFontSize, color: _colorSecondary),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: _headerAfterInfoGap),
            pw.Divider(color: _colorDivider, thickness: _dividerThickness),
            pw.SizedBox(height: _headerAfterDividerGap),
          ],
        ),
        // ---- Page footer
        footer: (context) => pw.Column(
          children: [
            pw.Divider(color: _colorDivider, thickness: _dividerThickness),
            pw.SizedBox(height: _footerBeforeTextGap),
            pw.Row(
              children: [
                pw.Text(
                  'Generated with Trade Estimate AI',
                  style: body(_smallFontSize, color: _colorSecondary),
                ),
                pw.Spacer(),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: body(_smallFontSize, color: _colorSecondary),
                ),
                pw.Spacer(),
                pw.Text(
                  estimate.id.length > 12
                      ? estimate.id.substring(0, 12)
                      : estimate.id,
                  style: body(_smallFontSize, color: _colorSecondary),
                ),
              ],
            ),
          ],
        ),
        // ---- Page body
        build: (context) => [
          // --- Client block
          pw.Text('Prepared for:', style: body(_sectionLabelFontSize, color: _colorSecondary)),
          pw.SizedBox(height: _clientNameGap),
          pw.Text(estimate.clientName ?? '—', style: body(_clientNameFontSize, bold: true)),
          if (estimate.clientEmail != null && estimate.clientEmail!.isNotEmpty)
            pw.Text(estimate.clientEmail!, style: body(_subBodyFontSize)),
          pw.SizedBox(height: _afterClientBlockGap),
          pw.Divider(color: _colorDivider, thickness: _dividerThickness),
          pw.SizedBox(height: _afterDividerSmallGap),

          // --- Scope of work
          pw.Text(
            'SCOPE OF WORK',
            style: pw.TextStyle(
              font: fontHelveticaBold,
              fontSize: _sectionLabelFontSize,
              color: _colorSecondary,
              letterSpacing: _sectionLabelSpacing,
            ),
          ),
          pw.SizedBox(height: _sectionLabelGap),
          pw.Text(
            estimate.aiGeneratedBody ?? 'No estimate body provided.',
            style: body(_bodyFontSize).copyWith(lineSpacing: _bodyLineSpacing),
          ),
          pw.SizedBox(height: _afterBodyTextGap),
          pw.Divider(color: _colorDivider, thickness: _dividerThickness),
          pw.SizedBox(height: _afterDividerSmallGap),

          // --- Cost summary
          pw.Text(
            'COST SUMMARY',
            style: pw.TextStyle(
              font: fontHelveticaBold,
              fontSize: _sectionLabelFontSize,
              color: _colorSecondary,
              letterSpacing: _sectionLabelSpacing,
            ),
          ),
          pw.SizedBox(height: _costSectionLabelGap),

          // Cost table — pw.Table for guaranteed column alignment
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(_costLabelColumnFlex),
              1: const pw.FlexColumnWidth(_costAmountColumnFlex),
            },
            children: [
              // Labor row
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: _itemSpacing),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Labor', style: body(_bodyFontSize)),
                        if (laborDetailText.isNotEmpty)
                          pw.Text(
                            laborDetailText,
                            style: body(_captionFontSize, color: _colorSecondary),
                          ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: _itemSpacing),
                    child: pw.Text(
                      fmtCurrency(laborCost),
                      style: mono(_bodyFontSize),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
              // Materials row
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: _itemSpacing),
                    child: pw.Text('Materials', style: body(_bodyFontSize)),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: _itemSpacing),
                    child: pw.Text(
                      fmtCurrency(materialsCost),
                      style: mono(_bodyFontSize),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
              // Additional fees row
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: _itemSpacing),
                    child: pw.Text('Additional Fees', style: body(_bodyFontSize)),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: _itemSpacing),
                    child: pw.Text(
                      fmtCurrency(additionalFees),
                      style: mono(_bodyFontSize),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: _afterCostTableGap),

          // Divider above TOTAL
          pw.Divider(color: _colorDivider, thickness: _dividerThickness),
          pw.SizedBox(height: _afterTotalDividerGap),

          // TOTAL row (bold, separate from table)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('TOTAL', style: body(_totalLabelFontSize, bold: true)),
              pw.Text(
                fmtCurrency(total),
                style: pw.TextStyle(
                  font: fontCourierBold,
                  fontSize: _totalAmountFontSize,
                  color: _colorPositive,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: _afterTotalGap),
          pw.Divider(color: _colorDivider, thickness: _dividerThickness),
          pw.SizedBox(height: _afterTermsDividerGap),

          // --- Terms & Conditions
          pw.Text(
            'TERMS & CONDITIONS',
            style: pw.TextStyle(
              font: fontHelveticaBold,
              fontSize: _termsLabelFontSize,
              letterSpacing: _sectionLabelSpacing,
            ),
          ),
          pw.SizedBox(height: _termsLabelGap),
          pw.Text(
            terms,
            style: body(_termsFontSize, color: _colorSecondary).copyWith(lineSpacing: _termsLineSpacing),
          ),
        ],
      ),
    );

    // ---- Save to temp directory
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${estimate.id}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }
}

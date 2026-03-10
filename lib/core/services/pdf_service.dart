import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

    String laborDetail() {
      final h = estimate.laborHours;
      final r = estimate.laborRate;
      if (h == null || r == null) return '';
      final hStr =
          h % 1 == 0 ? h.toInt().toString() : h.toStringAsFixed(1);
      return '($hStr hrs × ${fmtCurrency(r)}/hr)';
    }

    final terms =
        'This estimate is valid for 30 days from the date above. Prices are subject '
        'to change if the scope of work changes. A deposit of 50% is required before '
        'work begins, with the balance due upon completion. This estimate does not '
        'include any permits unless explicitly stated. $businessName is not responsible '
        'for unforeseen conditions discovered during the work that require additional '
        'materials or labor.';

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
        margin: const pw.EdgeInsets.all(36), // 0.5 inch
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
                      pw.Text(businessName, style: body(14, bold: true)),
                      if (profile.phone != null && profile.phone!.isNotEmpty)
                        pw.Text(profile.phone!, style: body(10, color: _colorSecondary)),
                      if (profile.email != null && profile.email!.isNotEmpty)
                        pw.Text(profile.email!, style: body(10, color: _colorSecondary)),
                      if (profile.licenseNumber != null &&
                          profile.licenseNumber!.isNotEmpty)
                        pw.Text(
                          'License #${profile.licenseNumber}',
                          style: body(10, color: _colorSecondary),
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
                        fontSize: 16,
                        color: _colorPositive,
                      ),
                    ),
                    pw.Text(
                      dateFormatter.format(estimate.createdAt),
                      style: body(10),
                    ),
                    pw.Text(
                      estimate.id.length > 12
                          ? estimate.id.substring(0, 12)
                          : estimate.id,
                      style: body(9, color: _colorSecondary),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: _colorDivider, thickness: 1),
            pw.SizedBox(height: 6),
          ],
        ),
        // ---- Page footer
        footer: (context) => pw.Column(
          children: [
            pw.Divider(color: _colorDivider, thickness: 1),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Text(
                  'Generated with Trade Estimate AI',
                  style: body(8, color: _colorSecondary),
                ),
                pw.Spacer(),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: body(8, color: _colorSecondary),
                ),
                pw.Spacer(),
                pw.Text(
                  estimate.id.length > 12
                      ? estimate.id.substring(0, 12)
                      : estimate.id,
                  style: body(8, color: _colorSecondary),
                ),
              ],
            ),
          ],
        ),
        // ---- Page body
        build: (context) => [
          // --- Client block
          pw.Text('Prepared for:', style: body(10, color: _colorSecondary)),
          pw.SizedBox(height: 4),
          pw.Text(estimate.clientName ?? '—', style: body(12, bold: true)),
          if (estimate.clientEmail != null && estimate.clientEmail!.isNotEmpty)
            pw.Text(estimate.clientEmail!, style: body(10)),
          pw.SizedBox(height: 8),
          pw.Divider(color: _colorDivider, thickness: 1),
          pw.SizedBox(height: 8),

          // --- Scope of work
          pw.Text(
            'SCOPE OF WORK',
            style: pw.TextStyle(
              font: fontHelveticaBold,
              fontSize: 10,
              color: _colorSecondary,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            estimate.aiGeneratedBody ?? 'No estimate body provided.',
            style: body(11).copyWith(lineSpacing: 4),
          ),
          pw.SizedBox(height: 12),
          pw.Divider(color: _colorDivider, thickness: 1),
          pw.SizedBox(height: 8),

          // --- Cost summary
          pw.Text(
            'COST SUMMARY',
            style: pw.TextStyle(
              font: fontHelveticaBold,
              fontSize: 10,
              color: _colorSecondary,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 8),

          // Labor row
          pw.Row(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Labor', style: body(11)),
                  if (laborDetail().isNotEmpty)
                    pw.Text(laborDetail(), style: body(9, color: _colorSecondary)),
                ],
              ),
              pw.Spacer(),
              pw.Text(fmtCurrency(laborCost), style: mono(11)),
            ],
          ),
          pw.SizedBox(height: 4),

          // Materials row
          pw.Row(
            children: [
              pw.Text('Materials', style: body(11)),
              pw.Spacer(),
              pw.Text(fmtCurrency(materialsCost), style: mono(11)),
            ],
          ),
          pw.SizedBox(height: 4),

          // Additional fees row
          pw.Row(
            children: [
              pw.Text('Additional Fees', style: body(11)),
              pw.Spacer(),
              pw.Text(fmtCurrency(additionalFees), style: mono(11)),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: _colorDivider, thickness: 1),
          pw.SizedBox(height: 6),

          // Total row
          pw.Row(
            children: [
              pw.Text('TOTAL', style: body(13, bold: true)),
              pw.Spacer(),
              pw.Text(
                fmtCurrency(total),
                style: pw.TextStyle(
                  font: fontCourierBold,
                  fontSize: 14,
                  color: _colorPositive,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(color: _colorDivider, thickness: 1),
          pw.SizedBox(height: 8),

          // --- Terms & Conditions
          pw.Text(
            'TERMS & CONDITIONS',
            style: pw.TextStyle(
              font: fontHelveticaBold,
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            terms,
            style: body(8, color: _colorSecondary).copyWith(lineSpacing: 2),
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

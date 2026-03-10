import '../models/estimate.dart';
import '../models/user_profile.dart';

class PdfService {
  static final PdfService _instance = PdfService._internal();
  factory PdfService() => _instance;
  PdfService._internal();

  // Fully implemented in Phase 6
  Future<String> generateAndSavePdf({
    required Estimate estimate,
    required UserProfile profile,
  }) async {
    throw UnimplementedError('PDF service will be implemented in Phase 6');
  }
}

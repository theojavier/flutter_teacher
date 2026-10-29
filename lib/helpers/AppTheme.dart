import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ---------- COLORS ----------
  static const Color bg = Color(0xFFF7F8F6);
  static const Color header = Color(0xFFFFFFFF);
  static const Color headerLight = Color(0xFFFCEBF0);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF121217);
  static const Color mutedText = Color(0xFF75777D);
  static const Color accent = Color(0xFFDF2D45);
  static const Color redDark = Color(0xFFB81935);
  static const Color redSoft = Color(0xFFFCEBF0);
  static const Color poster = Color(0xFFEA3C50);
  static const Color success = Color(0xFF27804A);
  static const Color error = Color(0xFFB81935);
  static const Color line = Color(0xFFDFE0DE);
  static const Color soft = Color(0xFFEFF0ED);

  // ---------- OPTIONAL: full Material ThemeData ----------
  /// Use in MaterialApp: theme: AppTheme.themeData
  static ThemeData get themeData => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.light(
      primary: accent,
      secondary: accent,
      surface: card,
      error: error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: header,
      foregroundColor: text,
      elevation: 0,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
    textTheme: GoogleFonts.interTextTheme(
      const TextTheme(
        bodyMedium: TextStyle(color: text),
        bodyLarge: TextStyle(color: text),
      ),
    ),
  );

  static TextStyle display(
    double size, {
    Color color = text,
    double ls = -0.05,
    double h = 1.05,
  }) => GoogleFonts.spaceGrotesk(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: size * ls,
    height: h,
  );

  static TextStyle mono(double size, {Color color = mutedText}) =>
      GoogleFonts.dmMono(
        fontSize: size,
        color: color,
        letterSpacing: size * 0.07,
      );

  // ---------- DECORATIONS ----------

  /// Flat bordered card used by the admin dashboard.
  static BoxDecoration cardDecoration() => BoxDecoration(
    borderRadius: BorderRadius.circular(11),
    color: card,
    border: Border.all(color: line),
  );

  /// Big hero/banner gradient (top welcome card)
  static BoxDecoration heroDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, headerLight],
      ),
      boxShadow: [
        BoxShadow(
          color: accent.withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  /// Glowing framed logo/avatar box (like the logo on HomePage)
  static Widget framedLogo({required Widget child, double size = 120}) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.9), accent.withOpacity(0.25)],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.35),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Container(
          color: card,
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );
  }

  /// Small dark pill/tag (e.g. "TRACK, MONITOR, AND EYE OPENER")
  static Widget pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFCEBF0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  /// Themed text field decoration (used by all form pages)
  static InputDecoration inputDecoration(
    String label, {
    String? helper,
    IconData? icon,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
    );

    return InputDecoration(
      filled: true,
      fillColor: soft,
      labelText: label,
      helperText: helper,
      helperStyle: const TextStyle(color: mutedText),
      labelStyle: const TextStyle(color: mutedText),
      floatingLabelStyle: const TextStyle(color: accent),
      errorStyle: const TextStyle(color: error),
      prefixIcon: icon == null ? null : Icon(icon, color: mutedText, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(Colors.white.withOpacity(0.12)),
      enabledBorder: border(Colors.white.withOpacity(0.12)),
      focusedBorder: border(accent, 1.5),
      errorBorder: border(error),
      focusedErrorBorder: border(error, 1.5),
    );
  }

  static ButtonStyle primaryButton({
    Color color = accent,
    Color foreground = Colors.white,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: foreground,
      disabledBackgroundColor: color.withOpacity(0.4),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.bold),
    );
  }

  static ButtonStyle ghostButton() {
    return TextButton.styleFrom(
      foregroundColor: mutedText,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // ---------- WIDGETS ----------

  /// Icon chip + title + divider line
  static Widget sectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: text,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: Colors.white.withOpacity(0.08)),
          ),
        ],
      ),
    );
  }

  /// Dashboard stat card (icon, big number, label)
  static Widget statCard({
    required IconData icon,
    required String title,
    required int count,
    Color color = accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 14),
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: mutedText),
          ),
        ],
      ),
    );
  }

  /// Empty-state card ("No results found", etc.)
  static Widget emptyCard(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: mutedText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Table cell text
  static Widget tableCell(
    String value, {
    Color color = text,
    FontWeight? weight,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 13, fontWeight: weight),
      ),
    );
  }

  /// Table card with the admin directory's light header and row separators.
  static Widget tableCard({
    required List<String> headers,
    required List<List<Widget>> rows,
    required Map<int, TableColumnWidth> columnWidths,
    double maxHeight = 350,
  }) {
    return Container(
      decoration: cardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: columnWidths,
              border: TableBorder(horizontalInside: BorderSide(color: line)),
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: soft),
                  children: [
                    for (final h in headers)
                      tableCell(h, weight: FontWeight.bold),
                  ],
                ),
                for (int i = 0; i < rows.length; i++)
                  TableRow(
                    decoration: BoxDecoration(color: i.isOdd ? bg : card),
                    children: rows[i],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rounded status chip (green = completed, red = otherwise)
  static Widget statusChip(String status, {String successValue = "completed"}) {
    final ok = status == successValue;
    final color = ok ? success : error;
    final label = status.isEmpty
        ? "—"
        : status[0].toUpperCase() + status.substring(1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// Loading skeleton block
  static Widget skeletonBlock(double height, {double radius = 18}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  /// Full-screen loading spinner in theme colors
  static Widget loadingScaffold() {
    return const Scaffold(
      backgroundColor: bg,
      body: Center(child: CircularProgressIndicator(color: accent)),
    );
  }

  /// Hide scrollbars/overscroll glow (wrap your scroll view with this)
  /// Hide scrollbars/overscroll glow (wrap your scroll view with this)
  static Widget noScrollbars(BuildContext context, {required Widget child}) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(scrollbars: false, overscroll: false),
      child: child,
    );
  }

  /// Framed icon used at the left of the AppBar title
  static Widget appBarIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.9), accent.withOpacity(0.25)],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.35),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: card,
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
  /// Blue empty-state card — original layout, blue icon and box.
static Widget emptyCardBlue(IconData icon, String message) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    decoration: cardDecoration(),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF153CFF).withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.notifications_none,
            color: Color(0xFF153CFF),
            size: 28,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: mutedText,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
}

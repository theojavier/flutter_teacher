import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ---------- COLORS ----------
  static const Color bg = Color(0xFF0B1220);
  static const Color header = Color(0xFF0F2B45);
  static const Color headerLight = Color(0xFF17456F);
  static const Color card = Color(0xFF0F3B61);
  static const Color text = Color(0xFFE6F0F8);
  static const Color mutedText = Color(0xFF9FB0C3);
  static const Color accent = Color(0xFF3D8BFF);
  static const Color success = Color(0xFF4ADE80);
  static const Color error = Color(0xFFF87171);

  // ---------- OPTIONAL: full Material ThemeData ----------
  /// Use in MaterialApp: theme: AppTheme.themeData
  static ThemeData get themeData => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
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
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: accent),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: text),
          bodyLarge: TextStyle(color: text),
        ),
      );

  // ---------- DECORATIONS ----------

  /// Standard gradient card (stat cards, tables, empty states, etc.)
  static BoxDecoration cardDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [card.withOpacity(0.9), card.withOpacity(0.55)],
      ),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  /// Big hero/banner gradient (top welcome card)
  static BoxDecoration heroDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [headerLight, header],
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.25),
          blurRadius: 16,
          offset: const Offset(0, 8),
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
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white70,
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
    fillColor: Colors.black.withOpacity(0.22),
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

  /// Table card: dark header strip, shaded alternate rows, scrollable
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
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              children: [
                TableRow(
                  decoration:
                      BoxDecoration(color: Colors.black.withOpacity(0.22)),
                  children: [
                    for (final h in headers)
                      tableCell(h, weight: FontWeight.bold),
                  ],
                ),
                for (int i = 0; i < rows.length; i++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: i.isOdd
                          ? Colors.white.withOpacity(0.03)
                          : Colors.transparent,
                    ),
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
    final label =
        status.isEmpty ? "—" : status[0].toUpperCase() + status.substring(1);

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
        color: Colors.white.withOpacity(0.06),
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
      behavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false, overscroll: false),
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
}   
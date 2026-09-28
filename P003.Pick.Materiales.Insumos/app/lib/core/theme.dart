import 'package:flutter/material.dart';

class AppColors {
  static const rojo = Color(0xFFD2001C);
  static const rojoOscuro = Color(0xFFB71C1C);
  static const blanco = Color(0xFFFFFFFF);
  static const fondo = Color(0xFFF7F7F7);
  static const texto = Color(0xFF212121);
  static const grisMedio = Color(0xFF757575);
  static const verdeOk = Color(0xFF2E7D32);
  static const ambarPendiente = Color(0xFFF9A825);
}

class AppTheme {
  static ThemeData get() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.rojo,
        primary: AppColors.rojo,
        secondary: AppColors.rojoOscuro,
        surface: AppColors.blanco,
        error: AppColors.rojoOscuro,
      ),
      scaffoldBackgroundColor: AppColors.fondo,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.rojo,
        foregroundColor: AppColors.blanco,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.blanco,
        elevation: 1,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.blanco,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.rojo, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.rojo,
          foregroundColor: AppColors.blanco,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.rojo,
          foregroundColor: AppColors.blanco,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
    return base;
  }
}

Color colorEstado(String estado) {
  switch (estado.toUpperCase()) {
    case 'SAP OK':
    case 'PROCESADO':
    case 'ENVIADO':
      return AppColors.verdeOk;
    case 'SAP NP':
    case 'ERROR':
      return AppColors.rojoOscuro;
    case 'ESPERANDO SAP':
    case 'PENDIENTE':
    case 'ABIERTA':
    case 'ENVIANDO':
      return AppColors.ambarPendiente;
    default:
      return AppColors.rojoOscuro;
  }
}

String estadoPick(String estadoTecnico, Object? estadoSap) {
  if (estadoTecnico.toUpperCase() != 'PROCESADO') return estadoTecnico;
  return switch (estadoSap?.toString().toUpperCase()) {
    'OK' => 'SAP OK',
    'NP' => 'SAP NP',
    _ => 'ESPERANDO SAP',
  };
}

class ChipEstado extends StatelessWidget {
  final String estado;
  const ChipEstado({super.key, required this.estado});

  @override
  Widget build(BuildContext context) {
    final c = colorEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado,
        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

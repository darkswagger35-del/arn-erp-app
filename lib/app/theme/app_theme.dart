import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF00B8C9);
  static const Color primaryDark = Color(0xFF073B4C);
  static const Color navy = Color(0xFF08192B);
  static const Color secondaryColor = Color(0xFF0E7490);
  static const Color accentColor = Color(0xFFFFA000);
  static const Color infoColor = Color(0xFF2563EB);
  static const Color successColor = Color(0xFF16A34A);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color surfaceColor = Color(0xFFF3F7FA);
  static const Color textColor = Color(0xFF17324D);

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(seedColor: primaryColor, brightness: Brightness.light).copyWith(
      primary: primaryDark, secondary: primaryColor, tertiary: accentColor,
      surface: Colors.white, error: dangerColor,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surfaceColor,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: navy, foregroundColor: Colors.white, elevation: 0,
        titleTextStyle: TextStyle(color: Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:.2),
      ),
      cardTheme: CardThemeData(
        elevation: 0, color: Colors.white, margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),side: const BorderSide(color: Color(0xFFDCE8EE))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled:true, fillColor:Colors.white, contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:15),
        border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:Color(0xFFD7E2E8))),
        enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:Color(0xFFD7E2E8))),
        focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:primaryColor,width:2)),
      ),
      filledButtonTheme: FilledButtonThemeData(style:FilledButton.styleFrom(
        backgroundColor:primaryColor,foregroundColor:navy,padding:const EdgeInsets.symmetric(horizontal:20,vertical:15),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),textStyle:const TextStyle(fontWeight:FontWeight.w800),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style:OutlinedButton.styleFrom(
        foregroundColor:primaryDark,side:const BorderSide(color:primaryColor),padding:const EdgeInsets.symmetric(horizontal:18,vertical:13),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
      )),
      chipTheme: ChipThemeData(backgroundColor:const Color(0xFFE3F7F9),selectedColor:const Color(0xFFBCECF1),labelStyle:const TextStyle(color:textColor,fontWeight:FontWeight.w700),side:BorderSide.none,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
      switchTheme: SwitchThemeData(
        thumbColor:WidgetStateProperty.resolveWith((s)=>s.contains(WidgetState.selected)?Colors.white:const Color(0xFF718096)),
        trackColor:WidgetStateProperty.resolveWith((s)=>s.contains(WidgetState.selected)?primaryColor:const Color(0xFFD5DEE3)),
      ),
      textTheme: const TextTheme(
        headlineSmall:TextStyle(color:textColor,fontWeight:FontWeight.w900),titleLarge:TextStyle(color:textColor,fontWeight:FontWeight.w900),
        titleMedium:TextStyle(color:textColor,fontWeight:FontWeight.w800),bodyLarge:TextStyle(color:textColor),bodyMedium:TextStyle(color:textColor),
      ),
    );
  }

  static ThemeData get darkTheme {
    final scheme=ColorScheme.fromSeed(seedColor:primaryColor,brightness:Brightness.dark).copyWith(
      primary:primaryColor,secondary:const Color(0xFF22D3EE),tertiary:accentColor,surface:const Color(0xFF0E2134),error:const Color(0xFFF87171));
    return ThemeData(
      useMaterial3:true,colorScheme:scheme,scaffoldBackgroundColor:const Color(0xFF061421),
      appBarTheme:const AppBarTheme(backgroundColor:navy,foregroundColor:Colors.white,elevation:0),
      cardTheme:CardThemeData(elevation:0,color:const Color(0xFF0E2134),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18),side:const BorderSide(color:Color(0xFF1B4051)))),
      inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:const Color(0xFF0E2134),border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)),focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:primaryColor,width:2))),
      filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(backgroundColor:primaryColor,foregroundColor:navy,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)))),
    );
  }
}

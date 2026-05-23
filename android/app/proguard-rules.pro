########################################
# FLUTTER CORE (OBBLIGATORIO)
########################################
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

########################################
# ANDROIDX / ANNOTATIONS
########################################
-keepattributes *Annotation*

########################################
# HIVE
########################################
-keep class * extends HiveObject { *; }
-keep class *Adapter { *; }

########################################
# SECURE STORAGE
########################################
-keep class com.it_nomads.fluttersecurestorage.** { *; }

########################################
# LOCAL AUTH
########################################
-keep class io.flutter.plugins.localauth.** { *; }

########################################
# FILE PICKER
########################################
-keep class com.mr.flutter.plugin.filepicker.** { *; }

########################################
# SHARE PLUS
########################################
-keep class dev.fluttercommunity.plus.share.** { *; }

########################################
# PDF / PRINTING
########################################
-keep class net.nfet.flutter.printing.** { *; }

########################################
# GOOGLE FONTS / OTHER COMMON LIBS
########################################
-keep class com.google.android.gms.** { *; }

########################################
# GOOGLE PLAY STORE (DEFERRED COMPONENTS)
########################################
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

########################################
# LOG REMOVAL (SAFE VERSION)
########################################
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
}
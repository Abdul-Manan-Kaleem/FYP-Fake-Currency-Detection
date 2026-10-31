# Not applied while isMinifyEnabled = false (see build.gradle.kts). Kept so
# shrinking can be re-enabled safely later.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google_mlkit_** { *; }
-keep class com.google.android.gms.common.** { *; }

# ML Kit text recognition references optional script packs (Chinese,
# Devanagari, Japanese, Korean) that this app does not bundle.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# TensorFlow Lite is called through JNI/FFI; keep it intact.
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.gpu.**

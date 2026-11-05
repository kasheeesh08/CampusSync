# NOTE: minification is currently disabled for release (build.gradle.kts); these rules
# document what was needed so far and are kept for when shrinking is re-enabled.
# Still missing when last tried: kotlin.Result (and possibly more kotlin.* classes).
# Release (R8) keep rules.
# shared_preferences_android 2.5.x calls SharedPreferencesApiRegistrar through
# JNI; R8 renamed it, crashing release builds at the first storage call
# ("NoSuchMethodError ... SharedPreferencesApiRegistrar.getAll"). The plugin
# ships no consumer rules, so keep its package explicitly.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
# The Dart-side JNI bridge (package:jni) looks up Kotlin coroutine types by
# name (e.g. Continuation in method signatures, CoroutineSingletons), so the
# coroutine runtime and the bridge's own classes must keep their names.
-keep class kotlin.coroutines.** { *; }
-keep class com.github.dart_lang.jni.** { *; }

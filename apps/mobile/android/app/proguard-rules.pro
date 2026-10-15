# flutter_local_notifications 18.x ships no consumer rules; R8 otherwise strips
# Gson generic signatures and plugin classes used via reflection
# ("Missing type parameter" crashes in release builds).
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

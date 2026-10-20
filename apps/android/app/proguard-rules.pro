-keepattributes *Annotation*, InnerClasses, Signature
-keepclassmembers @kotlinx.serialization.Serializable class ** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}

# OkHttp / Okio ship their own consumer rules; these silence optional-platform warnings.
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
# Tink (security-crypto) references annotations not on the runtime classpath.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-keep class com.huanmeng.huanhermes.core.**.*$$serializer { *; }

# Rhino (local agent JS sandbox) loads parts of its runtime reflectively.
-keep class org.mozilla.javascript.** { *; }
-dontwarn org.mozilla.javascript.**
-dontwarn javax.lang.model.**
-dontwarn java.beans.**
-dontwarn jdk.dynalink.**
# pdfbox-android optional JPEG2000 decoder.
-dontwarn com.gemalto.jp2.**
-keep class com.tom_roush.pdfbox.** { *; }
-keep class com.tom_roush.fontbox.** { *; }
# jsoup optional re2j.
-dontwarn com.google.re2j.**

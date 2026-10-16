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

# 只在本 App 里需要的 R8 规则。
#
# 为什么必须有这个文件：`com.microsoft.onnxruntime:onnxruntime-android` 的 aar
# **不带 consumer proguard 规则**，而它的 native 层（libonnxruntime4j_jni.so）
# 是按**类名字符串**去找 Java 类的：
#
#   convertToTensorInfo -> GetMethodID(env, javaClass, ...)
#
# R8 在 release 里把 `ai.onnxruntime.TensorInfo` 混淆成 `yr0` 之后，
# 那句按名字查找就拿到 null class，JNI 检查到 `java_class == null` 直接 abort，
# 进程收到 SIGABRT 闪退 —— 栈里的原话是：
#
#   JNI DETECTED ERROR IN APPLICATION: java_class == null
#       in call to GetMethodID
#       from boolean[] ai.onnxruntime.OrtSession.run(...)
#
# debug 构建不做 R8，所以 debug 下无论跑多少遍都是好的。
# 用户看到的「一点处理就闪退」就是这一条。

# ONNX Runtime 的 Java 层全部保留原类名，native 侧靠名字找它们。
-keep class ai.onnxruntime.** { *; }

# 保险起见连成员名也不改：native 侧还可能按方法名查（比如 run 的重载）。
-keepclassmembers class ai.onnxruntime.** { *; }

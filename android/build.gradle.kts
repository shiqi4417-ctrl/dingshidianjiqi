allprojects {
    repositories {
        // [本机改动] 同上：只保留可达的阿里云镜像与 Maven Central，
        // 不声明 google()（会指向不可达的 dl.google.com/dl/android/maven2）。
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        mavenCentral()
        // Flutter 引擎构件(io.flutter:arm64_v8a_release 等)官方在 download.flutter.io。
        // dl.google.com 被墙、tuna 未同步该仓库；腾讯镜像已验证可达且含完整引擎构件，故加入。
        maven { url = uri("https://mirrors.cloud.tencent.com/flutter/download.flutter.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

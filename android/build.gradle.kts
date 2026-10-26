plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.ktlint) apply false
}

// One formatter for every module: ktlintFormat rewrites, ktlintCheck verifies.
subprojects {
    apply(plugin = "org.jlleitschuh.gradle.ktlint")
}

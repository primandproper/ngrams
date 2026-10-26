plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(libs.kotlinx.serialization.json)

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(kotlin("test"))
    testRuntimeOnly(libs.junit.platform.launcher)
}

sourceSets {
    test {
        // The fixtures the iOS tests run too, and the real bank, so tests read what ships.
        resources.srcDir("../../testdata")
        resources.srcDir("../../data/bank")
    }
}

tasks.test {
    useJUnitPlatform()
}

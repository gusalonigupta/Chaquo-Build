plugins {
    id("com.chaquo.python") version "16.1.0" apply false
    id("com.android.library") version "8.4.1" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
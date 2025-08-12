plugins {
    id("com.android.library")
    id("com.chaquo.python")
}

android {
    namespace = "lib"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
    }

    flavorDimensions += "abi"

    productFlavors {
        create("abi32") {
            dimension = "abi"
            ndk {
                abiFilters += listOf("x86", "armeabi-v7a")
            }
        }
        create("abi64") {
            dimension = "abi"
            ndk {
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

val pipPackages = listOf(
    "yt-dlp",
    "pycryptodomex",
    "certifi",
    "mutagen",
    "websockets",
    "brotli",
    "aria2p",
    "PySocks",
    "httpx",
    "pyOpenSSL",
    "pycurl"
)

chaquopy {
    defaultConfig {
        pip {
            options("--upgrade")
            pipPackages.forEach { install(it) }
        }
    }

    productFlavors {
        getByName("abi32") {
            version = "3.11"
        }
        getByName("abi64") {
            version = "3.12"
        }
    }
}
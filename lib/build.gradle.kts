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
                abiFilters += listOf("armeabi-v7a", "x86")
            }
        }
        create("abi64") {
            dimension = "abi"
            ndk {
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }        
        create("arm64") {
            dimension = "abi"
            ndk {
                abiFilters += "arm64-v8a"
            }
        }
        create("arm32") {
            dimension = "abi"
            ndk {
                abiFilters += "armeabi-v7a"
            }
        }
        create("x86_64") {
            dimension = "abi"
            ndk {
                abiFilters += "x86_64"
            }
        }
        create("x86") {
            dimension = "abi"
            ndk {
                abiFilters += "x86"
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
    productFlavors {
        getByName("abi32") {
            version = "3.11"
            pip {
                options("--upgrade")
                pipPackages.forEach { install(it) }
            }
        }
        getByName("abi64") {
            version = "3.12"
            pip {
                options("--upgrade")
                pipPackages.forEach { install(it) }
            }
        }
        getByName("arm64") {
            version = "3.12"
            pip {
                options("--upgrade")
                pipPackages.forEach { install(it) }
            }
        }
        getByName("arm32") {
            version = "3.11"
            pip {
                options("--upgrade")
                pipPackages.forEach { install(it) }
            }
        }
        getByName("x86_64") {
            version = "3.12"
            pip {
                options("--upgrade")
                pipPackages.forEach { install(it) }
            }
        }
        getByName("x86") {
            version = "3.11"
            pip {
                options("--upgrade")
                pipPackages.forEach { install(it) }
            }
        }
    }
}
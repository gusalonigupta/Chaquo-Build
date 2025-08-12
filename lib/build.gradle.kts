plugins {
    id("com.android.library")
    id("com.chaquo.python")
}

android {
    namespace = "lib"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        targetSdk = 34
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
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

chaquopy {
    productFlavors {
        getByName("abi32") {
            version = "3.11"
            pip {
                options("--upgrade")
                installAll()
            }
        }
        getByName("abi64") {
            version = "3.12"
            pip {
                options("--upgrade")
                installAll()
            }
        }
    }
}


fun com.chaquo.python.PythonExtension.PipScope.installAll() {
    install("yt-dlp")
    install("pycryptodomex")
    install("certifi")
    install("mutagen")
    install("websockets")
    install("brotli")
    install("aria2p")
    install("PySocks")
    install("httpx")
    install("pyOpenSSL")
    install("pycurl")
}

dependencies {
}
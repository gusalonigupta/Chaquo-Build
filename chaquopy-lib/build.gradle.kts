plugins {
    id("com.android.library")
    id("com.chaquo.python")
}

android {
    namespace = "com.example.pybridge"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        targetSdk = 34

        ndk {
            abiFilters += listOf("arm64-v8a") // add other ABIs if needed
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

chaquopy {
    defaultConfig {
        pip {
            options("--upgrade")
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
    }
}

dependencies {
    // no java/kotlin dependencies, keep clean
}
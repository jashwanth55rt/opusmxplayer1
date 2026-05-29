#!/usr/bin/env bash
###############################################################################
# build.sh
#
# Builds the "javagoat" Android video player app (an MX Player style clone)
# from scratch on a Linux machine and produces a SIGNED RELEASE APK.
#
# Package : com.example.mxplayer
# App label: javagoat
#
# Requirements on the host:
#   - JDK 17 (Android Gradle Plugin 8.2.0 requires Java 17)
#   - wget, unzip, sudo
#   - Internet access to dl.google.com and services.gradle.org
#
# The final APK will be at:
#   app/build/outputs/apk/release/app-release.apk
###############################################################################

set -euo pipefail

# -----------------------------------------------------------------------------
# 0a. JDK version guard
#
# Android Gradle Plugin 8.2.0 requires Java 17 or newer, while Gradle 8.2 only
# supports up to Java 20. Fail fast with a clear message if the active JDK is
# outside the 17-20 range so the build does not die later with a cryptic error.
# -----------------------------------------------------------------------------
if ! command -v java >/dev/null 2>&1; then
  echo "ERROR: 'java' was not found on PATH. Install a JDK in the 17-20 range." >&2
  echo "       On this sandbox you can run:  mise use -g java@17" >&2
  exit 1
fi

JAVA_RAW="$(java -version 2>&1 | head -1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1)"
JAVA_MAJOR="${JAVA_RAW%%.*}"
# Handle the legacy "1.8"-style version scheme.
if [ "${JAVA_MAJOR}" = "1" ]; then
  JAVA_MAJOR="$(echo "${JAVA_RAW}" | cut -d. -f2)"
fi

if [ -z "${JAVA_MAJOR}" ] || [ "${JAVA_MAJOR}" -lt 17 ] || [ "${JAVA_MAJOR}" -gt 20 ]; then
  echo "ERROR: Detected Java ${JAVA_RAW:-unknown}. This build needs JDK 17-20" >&2
  echo "       (AGP 8.2.0 requires Java 17+, Gradle 8.2 supports up to Java 20)." >&2
  echo "       On this sandbox you can run:  mise use -g java@17" >&2
  exit 1
fi
echo ">>> Using Java ${JAVA_RAW} (major ${JAVA_MAJOR}) - OK"

# -----------------------------------------------------------------------------
# 0. Project identity / paths
# -----------------------------------------------------------------------------
PROJECT_ROOT="$(pwd)"
PKG_PATH="app/src/main/java/com/example/mxplayer"
RES="app/src/main/res"

echo ">>> Project root: ${PROJECT_ROOT}"

mkdir -p \
  "app/src/main/java/com/example/mxplayer" \
  "${RES}/values" \
  "${RES}/drawable" \
  "${RES}/layout" \
  "${RES}/mipmap-anydpi-v26"

# -----------------------------------------------------------------------------
# 1. Android SDK setup
# -----------------------------------------------------------------------------
echo ">>> Setting up Android SDK..."
export ANDROID_HOME="${HOME}/android-sdk"

if [ ! -d "${ANDROID_HOME}/cmdline-tools/latest/bin" ]; then
  mkdir -p "${ANDROID_HOME}/cmdline-tools"
  (
    cd "${ANDROID_HOME}/cmdline-tools"
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip
    unzip -q commandlinetools-linux-10406996_latest.zip
    mv cmdline-tools latest
    rm -f commandlinetools-linux-10406996_latest.zip
  )
fi

export PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

# Accept all licenses silently and install the exact packages requested.
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platforms;android-34" "build-tools;34.0.0" "platform-tools"

# local.properties points Gradle at the SDK (absolute path).
cat > local.properties <<EOF
sdk.dir=${ANDROID_HOME}
EOF

# -----------------------------------------------------------------------------
# 2. Root Gradle files
# -----------------------------------------------------------------------------
echo ">>> Writing root Gradle files..."

cat > settings.gradle <<'EOF'
include ':app'
EOF

cat > gradle.properties <<'EOF'
android.useAndroidX=true
android.enableJetifier=true
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
EOF

cat > build.gradle <<'EOF'
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.2.0'
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' }
    }
}

tasks.register('clean', Delete) {
    delete rootProject.buildDir
}
EOF

# -----------------------------------------------------------------------------
# 3. app/build.gradle
# -----------------------------------------------------------------------------
echo ">>> Writing app/build.gradle..."

cat > app/build.gradle <<'EOF'
plugins {
    id 'com.android.application'
}

android {
    namespace 'com.example.mxplayer'
    compileSdk 34

    defaultConfig {
        applicationId "com.example.mxplayer"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }

    signingConfigs {
        release {
            storeFile file("../my-release-key.jks")
            storePassword "mypassword123"
            keyAlias "my-key-alias"
            keyPassword "mypassword123"
        }
    }

    buildTypes {
        release {
            minifyEnabled false
            signingConfig signingConfigs.release
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

dependencies {
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.10.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    implementation 'androidx.cardview:cardview:1.0.0'
    implementation 'androidx.media3:media3-exoplayer:1.2.0'
    implementation 'androidx.media3:media3-ui:1.2.0'
    implementation 'com.github.bumptech.glide:glide:4.16.0'
}
EOF

# -----------------------------------------------------------------------------
# 4. Keystore (RSA 2048, 10000 days) - errors suppressed if it already exists
# -----------------------------------------------------------------------------
echo ">>> Generating release keystore..."
keytool -genkeypair -v \
  -keystore my-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias my-key-alias \
  -storepass mypassword123 -keypass mypassword123 \
  -dname "CN=javagoat, OU=ID, O=Example, L=City, S=State, C=US" || true

# -----------------------------------------------------------------------------
# 5. AndroidManifest.xml
# -----------------------------------------------------------------------------
echo ">>> Writing AndroidManifest.xml..."

cat > app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission
        android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />

    <application
        android:allowBackup="true"
        android:label="javagoat"
        android:requestLegacyExternalStorage="true"
        android:usesCleartextTraffic="true"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:theme="@style/Theme.MXClone">

        <activity
            android:name=".SplashActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name=".MainActivity"
            android:exported="false" />

        <activity
            android:name=".PlayerActivity"
            android:exported="false"
            android:screenOrientation="sensor"
            android:configChanges="orientation|keyboardHidden|screenSize|smallestScreenSize|screenLayout" />
    </application>
</manifest>
EOF

# -----------------------------------------------------------------------------
# 6. Resources: colors, theme, drawables
# -----------------------------------------------------------------------------
echo ">>> Writing resources (colors, theme, drawables)..."

cat > "${RES}/values/colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="primary">#0F0F0F</color>
    <color name="primary_dark">#000000</color>
    <color name="accent">#E53935</color>
    <color name="bg_dark">#0A0A0A</color>
    <color name="surface_dark">#1A1A1A</color>
    <color name="text_light">#FFFFFF</color>
    <color name="text_secondary">#9E9E9E</color>
</resources>
EOF

cat > "${RES}/values/themes.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.MXClone" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="colorPrimary">@color/primary</item>
        <item name="colorPrimaryDark">@color/primary_dark</item>
        <item name="colorAccent">@color/accent</item>
        <item name="android:statusBarColor">@color/primary_dark</item>
        <item name="android:windowBackground">@color/bg_dark</item>
    </style>
</resources>
EOF

cat > "${RES}/drawable/bg_duration.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#CC000000" />
    <corners android:radius="4dp" />
</shape>
EOF

# -----------------------------------------------------------------------------
# 7. Layouts
# -----------------------------------------------------------------------------
echo ">>> Writing layouts..."

cat > "${RES}/layout/activity_splash.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/bg_dark">

    <TextView
        android:id="@+id/splashText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_centerInParent="true"
        android:text="javagoat"
        android:textColor="#E53935"
        android:textSize="44sp"
        android:textStyle="bold"
        android:letterSpacing="0.05"
        android:alpha="0" />
</RelativeLayout>
EOF

cat > "${RES}/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.coordinatorlayout.widget.CoordinatorLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/bg_dark">

    <com.google.android.material.appbar.AppBarLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@color/primary">

        <androidx.appcompat.widget.Toolbar
            android:id="@+id/toolbar"
            android:layout_width="match_parent"
            android:layout_height="?attr/actionBarSize"
            android:background="@color/primary"
            app:title="Local Videos"
            app:titleTextColor="@color/text_light" />
    </com.google.android.material.appbar.AppBarLayout>

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/videoRecyclerView"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:paddingTop="8dp"
        android:paddingBottom="8dp"
        android:clipToPadding="false"
        app:layout_behavior="@string/appbar_scrolling_view_behavior" />

    <ProgressBar
        android:id="@+id/progressBar"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:visibility="gone" />

    <TextView
        android:id="@+id/emptyText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:text="No videos found"
        android:textColor="@color/text_secondary"
        android:visibility="gone" />
</androidx.coordinatorlayout.widget.CoordinatorLayout>
EOF

cat > "${RES}/layout/item_video.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:padding="12dp"
    android:background="?attr/selectableItemBackground">

    <androidx.cardview.widget.CardView
        android:layout_width="140dp"
        android:layout_height="80dp"
        app:cardBackgroundColor="@color/surface_dark"
        app:cardCornerRadius="8dp"
        app:cardElevation="0dp">

        <RelativeLayout
            android:layout_width="match_parent"
            android:layout_height="match_parent">

            <ImageView
                android:id="@+id/videoThumbnail"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="centerCrop" />

            <TextView
                android:id="@+id/videoDuration"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_alignParentEnd="true"
                android:layout_alignParentBottom="true"
                android:layout_margin="4dp"
                android:background="@drawable/bg_duration"
                android:paddingStart="6dp"
                android:paddingEnd="6dp"
                android:paddingTop="2dp"
                android:paddingBottom="2dp"
                android:textColor="#FFFFFF"
                android:textSize="11sp"
                android:textStyle="bold" />
        </RelativeLayout>
    </androidx.cardview.widget.CardView>

    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:layout_gravity="center_vertical"
        android:orientation="vertical"
        android:paddingStart="16dp"
        android:paddingEnd="8dp">

        <TextView
            android:id="@+id/videoTitle"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:maxLines="2"
            android:ellipsize="end"
            android:textColor="#FFFFFF"
            android:textSize="15sp" />

        <TextView
            android:id="@+id/videoSize"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="6dp"
            android:textColor="@color/text_secondary"
            android:textSize="13sp" />
    </LinearLayout>

    <ImageView
        android:layout_width="24dp"
        android:layout_height="24dp"
        android:layout_gravity="center_vertical"
        android:src="@android:drawable/ic_menu_more"
        app:tint="@color/text_secondary" />
</LinearLayout>
EOF

cat > "${RES}/layout/activity_player.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">

    <androidx.media3.ui.PlayerView
        android:id="@+id/playerView"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        app:use_controller="true"
        app:resize_mode="fit" />

    <LinearLayout
        android:id="@+id/indicatorLayout"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:background="@drawable/bg_duration"
        android:padding="24dp"
        android:orientation="vertical"
        android:visibility="gone">

        <TextView
            android:id="@+id/indicatorText"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textColor="#FFFFFF"
            android:textSize="22sp"
            android:textStyle="bold" />
    </LinearLayout>
</FrameLayout>
EOF

# -----------------------------------------------------------------------------
# 8. Icons
# -----------------------------------------------------------------------------
echo ">>> Writing launcher icons..."

cat > "${RES}/drawable/ic_launcher_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#E53935" />
</shape>
EOF

cat > "${RES}/drawable/ic_launcher_foreground.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M8,5v14l11,-7z" />
</vector>
EOF

cat > "${RES}/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
EOF

cp "${RES}/mipmap-anydpi-v26/ic_launcher.xml" "${RES}/mipmap-anydpi-v26/ic_launcher_round.xml"

# -----------------------------------------------------------------------------
# 9. Java sources
# -----------------------------------------------------------------------------
echo ">>> Writing Java sources..."

cat > "${PKG_PATH}/SplashActivity.java" <<'EOF'
package com.example.mxplayer;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

public class SplashActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_splash);

        TextView splashText = findViewById(R.id.splashText);
        splashText.animate()
                .alpha(1f)
                .scaleX(1.2f)
                .scaleY(1.2f)
                .setDuration(1200)
                .withEndAction(() ->
                        new Handler(Looper.getMainLooper()).postDelayed(() -> {
                            startActivity(new Intent(SplashActivity.this, MainActivity.class));
                            finish();
                        }, 400))
                .start();
    }
}
EOF

cat > "${PKG_PATH}/MainActivity.java" <<'EOF'
package com.example.mxplayer;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.bumptech.glide.Glide;
import com.bumptech.glide.load.engine.DiskCacheStrategy;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class MainActivity extends AppCompatActivity {

    private static final int PERMISSION_REQUEST_CODE = 100;

    private RecyclerView videoRecyclerView;
    private ProgressBar progressBar;
    private TextView emptyText;
    private final List<VideoModel> videoList = new ArrayList<>();
    private VideoAdapter adapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        Toolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);

        videoRecyclerView = findViewById(R.id.videoRecyclerView);
        progressBar = findViewById(R.id.progressBar);
        emptyText = findViewById(R.id.emptyText);

        videoRecyclerView.setLayoutManager(new LinearLayoutManager(this));
        adapter = new VideoAdapter(videoList, video -> {
            Intent intent = new Intent(MainActivity.this, PlayerActivity.class);
            intent.putExtra("videoPath", video.path);
            intent.putExtra("videoTitle", video.title);
            startActivity(intent);
        });
        videoRecyclerView.setAdapter(adapter);

        checkPermissionAndLoad();
    }

    private void checkPermissionAndLoad() {
        String permission;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permission = Manifest.permission.READ_MEDIA_VIDEO;
        } else {
            permission = Manifest.permission.READ_EXTERNAL_STORAGE;
        }

        if (ContextCompat.checkSelfPermission(this, permission)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this,
                    new String[]{permission}, PERMISSION_REQUEST_CODE);
        } else {
            loadVideos();
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode,
                                           @NonNull String[] permissions,
                                           @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.length > 0
                    && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                loadVideos();
            } else {
                progressBar.setVisibility(View.GONE);
                emptyText.setVisibility(View.VISIBLE);
            }
        }
    }

    private void loadVideos() {
        progressBar.setVisibility(View.VISIBLE);
        emptyText.setVisibility(View.GONE);

        new Thread(() -> {
            List<VideoModel> videos = new ArrayList<>();
            String[] projection = {
                    MediaStore.Video.Media.DATA,
                    MediaStore.Video.Media.TITLE,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE
            };
            String sortOrder = MediaStore.Video.Media.DATE_ADDED + " DESC";

            try (Cursor cursor = getContentResolver().query(
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                    projection, null, null, sortOrder)) {
                if (cursor != null) {
                    int dataCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA);
                    int titleCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.TITLE);
                    int durationCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION);
                    int sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE);

                    while (cursor.moveToNext()) {
                        String path = cursor.getString(dataCol);
                        if (path == null || !new File(path).exists()) {
                            continue;
                        }
                        String title = cursor.getString(titleCol);
                        long duration = cursor.getLong(durationCol);
                        long size = cursor.getLong(sizeCol);
                        videos.add(new VideoModel(path, title, duration, size));
                    }
                }
            }

            runOnUiThread(() -> {
                progressBar.setVisibility(View.GONE);
                videoList.clear();
                videoList.addAll(videos);
                adapter.notifyDataSetChanged();
                emptyText.setVisibility(videoList.isEmpty() ? View.VISIBLE : View.GONE);
            });
        }).start();
    }

    static class VideoModel {
        String path;
        String title;
        long duration;
        long size;

        VideoModel(String path, String title, long duration, long size) {
            this.path = path;
            this.title = title;
            this.duration = duration;
            this.size = size;
        }
    }

    static class VideoAdapter extends RecyclerView.Adapter<VideoAdapter.VideoViewHolder> {

        interface OnVideoClickListener {
            void onVideoClick(VideoModel video);
        }

        private final List<VideoModel> videos;
        private final OnVideoClickListener listener;

        VideoAdapter(List<VideoModel> videos, OnVideoClickListener listener) {
            this.videos = videos;
            this.listener = listener;
        }

        @NonNull
        @Override
        public VideoViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_video, parent, false);
            return new VideoViewHolder(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VideoViewHolder holder, int position) {
            VideoModel video = videos.get(position);
            holder.videoTitle.setText(video.title);
            holder.videoDuration.setText(formatDuration(video.duration));
            holder.videoSize.setText(formatSize(video.size));

            Glide.with(holder.itemView.getContext())
                    .load(Uri.fromFile(new File(video.path)))
                    .diskCacheStrategy(DiskCacheStrategy.ALL)
                    .placeholder(android.R.color.darker_gray)
                    .into(holder.videoThumbnail);

            holder.itemView.setOnClickListener(v -> {
                if (listener != null) {
                    listener.onVideoClick(video);
                }
            });
        }

        @Override
        public int getItemCount() {
            return videos.size();
        }

        private String formatDuration(long durationMs) {
            long totalSeconds = durationMs / 1000;
            long hours = totalSeconds / 3600;
            long minutes = (totalSeconds % 3600) / 60;
            long seconds = totalSeconds % 60;
            if (totalSeconds >= 3600) {
                return String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds);
            } else {
                return String.format(Locale.US, "%02d:%02d", minutes, seconds);
            }
        }

        private String formatSize(long size) {
            if (size >= 1073741824L) {
                return String.format(Locale.US, "%.2f GB", size / 1073741824.0);
            } else {
                return String.format(Locale.US, "%.2f MB", size / 1048576.0);
            }
        }

        static class VideoViewHolder extends RecyclerView.ViewHolder {
            ImageView videoThumbnail;
            TextView videoDuration;
            TextView videoTitle;
            TextView videoSize;

            VideoViewHolder(@NonNull View itemView) {
                super(itemView);
                videoThumbnail = itemView.findViewById(R.id.videoThumbnail);
                videoDuration = itemView.findViewById(R.id.videoDuration);
                videoTitle = itemView.findViewById(R.id.videoTitle);
                videoSize = itemView.findViewById(R.id.videoSize);
            }
        }
    }
}
EOF

cat > "${PKG_PATH}/PlayerActivity.java" <<'EOF'
package com.example.mxplayer;

import android.content.Context;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.media3.common.MediaItem;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.PlayerView;

@UnstableApi
public class PlayerActivity extends AppCompatActivity {

    private PlayerView playerView;
    private ExoPlayer player;
    private LinearLayout indicatorLayout;
    private TextView indicatorText;

    private GestureDetector gestureDetector;
    private ScaleGestureDetector scaleGestureDetector;
    private AudioManager audioManager;

    private float scaleFactor = 1.0f;
    private int screenWidth;
    private int screenHeight;
    private boolean isLeftHalf;

    private final Handler handler = new Handler(Looper.getMainLooper());

    private String videoPath;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_player);

        playerView = findViewById(R.id.playerView);
        indicatorLayout = findViewById(R.id.indicatorLayout);
        indicatorText = findViewById(R.id.indicatorText);

        videoPath = getIntent().getStringExtra("videoPath");

        audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

        screenWidth = getResources().getDisplayMetrics().widthPixels;
        screenHeight = getResources().getDisplayMetrics().heightPixels;

        scaleGestureDetector = new ScaleGestureDetector(this,
                new ScaleGestureDetector.SimpleOnScaleGestureListener() {
                    @Override
                    public boolean onScale(@NonNull ScaleGestureDetector detector) {
                        scaleFactor *= detector.getScaleFactor();
                        scaleFactor = Math.max(0.5f, Math.min(scaleFactor, 5.0f));
                        View surface = playerView.getVideoSurfaceView();
                        if (surface != null) {
                            surface.setScaleX(scaleFactor);
                            surface.setScaleY(scaleFactor);
                        }
                        return true;
                    }
                });

        gestureDetector = new GestureDetector(this,
                new GestureDetector.SimpleOnGestureListener() {
                    @Override
                    public boolean onDown(@NonNull MotionEvent e) {
                        isLeftHalf = e.getX() < screenWidth / 2f;
                        return true;
                    }

                    @Override
                    public boolean onScroll(@Nullable MotionEvent e1, @NonNull MotionEvent e2,
                                            float distanceX, float distanceY) {
                        if (e1 == null) {
                            return false;
                        }
                        float deltaX = e2.getX() - e1.getX();
                        float deltaY = e2.getY() - e1.getY();
                        if (Math.abs(deltaX) > Math.abs(deltaY)) {
                            return false;
                        }

                        float percent = (e1.getY() - e2.getY()) / screenHeight;

                        if (isLeftHalf) {
                            WindowManager.LayoutParams lp = getWindow().getAttributes();
                            float brightness = lp.screenBrightness;
                            if (brightness < 0) {
                                brightness = 0.5f;
                            }
                            brightness += percent * 1.5f;
                            brightness = Math.max(0.01f, Math.min(brightness, 1.0f));
                            lp.screenBrightness = brightness;
                            getWindow().setAttributes(lp);
                            showIndicator("\u2600 " + (int) (brightness * 100) + "%");
                        } else {
                            int maxVolume =
                                    audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
                            int change = (int) (percent * maxVolume * 1.5f);
                            if (change == 0) {
                                return true;
                            }
                            int current =
                                    audioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
                            int newVolume = Math.max(0, Math.min(current + change, maxVolume));
                            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, newVolume, 0);
                            showIndicator("\uD83D\uDD0A " + (int) (newVolume * 100f / maxVolume) + "%");
                        }
                        return true;
                    }

                    @Override
                    public boolean onDoubleTap(@NonNull MotionEvent e) {
                        if (playerView.getResizeMode() == AspectRatioFrameLayout.RESIZE_MODE_FIT) {
                            playerView.setResizeMode(AspectRatioFrameLayout.RESIZE_MODE_ZOOM);
                            showIndicator("Crop to Fit");
                        } else {
                            playerView.setResizeMode(AspectRatioFrameLayout.RESIZE_MODE_FIT);
                            showIndicator("Fit Screen");
                        }
                        scaleFactor = 1.0f;
                        View surface = playerView.getVideoSurfaceView();
                        if (surface != null) {
                            surface.setScaleX(1.0f);
                            surface.setScaleY(1.0f);
                        }
                        return true;
                    }
                });
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent ev) {
        scaleGestureDetector.onTouchEvent(ev);
        gestureDetector.onTouchEvent(ev);
        return super.dispatchTouchEvent(ev);
    }

    private void showIndicator(String text) {
        indicatorText.setText(text);
        indicatorLayout.setVisibility(View.VISIBLE);
        handler.removeCallbacksAndMessages(null);
        handler.postDelayed(() -> indicatorLayout.setVisibility(View.GONE), 1000);
    }

    private void initializePlayer() {
        if (player == null) {
            player = new ExoPlayer.Builder(this).build();
            playerView.setPlayer(player);
            if (videoPath != null) {
                MediaItem mediaItem = MediaItem.fromUri(Uri.parse(videoPath));
                player.setMediaItem(mediaItem);
                player.prepare();
                player.play();
            }
        }
    }

    @Override
    protected void onStart() {
        super.onStart();
        initializePlayer();
    }

    @Override
    protected void onResume() {
        super.onResume();
        hideSystemUI();
        if (player == null) {
            initializePlayer();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (player != null) {
            player.pause();
        }
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (player != null) {
            player.release();
            player = null;
        }
    }

    private void hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowInsetsController controller = getWindow().getInsetsController();
            if (controller != null) {
                controller.hide(WindowInsets.Type.statusBars()
                        | WindowInsets.Type.navigationBars());
                controller.setSystemBarsBehavior(
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                            | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
    }
}
EOF

# -----------------------------------------------------------------------------
# 10. Gradle wrapper (Gradle 8.2)
# -----------------------------------------------------------------------------
echo ">>> Setting up Gradle 8.2 wrapper..."

if [ ! -x "/opt/gradle/gradle-8.2/bin/gradle" ]; then
  wget -q https://services.gradle.org/distributions/gradle-8.2-bin.zip
  sudo unzip -q -d /opt/gradle gradle-8.2-bin.zip
  rm -f gradle-8.2-bin.zip
fi

/opt/gradle/gradle-8.2/bin/gradle wrapper --gradle-version 8.2
chmod +x gradlew

# -----------------------------------------------------------------------------
# 11. Final build
# -----------------------------------------------------------------------------
echo ">>> Building signed release APK..."
./gradlew clean assembleRelease

echo ""
echo ">>> BUILD COMPLETE"
echo ">>> Signed release APK: app/build/outputs/apk/release/app-release.apk"

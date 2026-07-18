FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Installa dipendenze base
RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip libglu1-mesa openjdk-17-jdk wget \
    && rm -rf /var/lib/apt/lists/*

USER vscode
WORKDIR /home/vscode

# Scarica e installa Android Command Line Tools
ENV ANDROID_SDK_ROOT=/home/vscode/android-sdk
RUN mkdir -p $ANDROID_SDK_ROOT/cmdline-tools \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline-tools.zip \
    && unzip -q cmdline-tools.zip -d $ANDROID_SDK_ROOT/cmdline-tools \
    && mv $ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools $ANDROID_SDK_ROOT/cmdline-tools/latest \
    && rm cmdline-tools.zip

# Configura variabili d'ambiente Android
ENV PATH=$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools

# Accetta le licenze Android
RUN yes | sdkmanager --licenses

# Installa Flutter
RUN git clone https://github.com/flutter/flutter.git -b stable /home/vscode/flutter
ENV PATH=$PATH:/home/vscode/flutter/bin

# Esegui il primo precache e il doctor
RUN flutter precache --android
RUN flutter doctor --android-licenses
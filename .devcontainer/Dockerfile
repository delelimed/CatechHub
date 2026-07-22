# Base d'appoggio ufficiale Ubuntu
FROM ubuntu:22.04

# Evita interazioni bloccanti durante l'installazione dei pacchetti
ENV DEBIAN_FRONTEND=noninteractive

# 1. Installa i prerequisiti di sistema e Java (Android richiede Java 17 per i Gradle moderni)
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    openjdk-17-jdk-headless \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# 2. Crea l'utente 'vscode' non-root con permessi di sudo (richiesto dal tuo devcontainer.json)
RUN useradd -m -s /bin/bash vscode && \
    echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER vscode
WORKDIR /home/vscode

# 3. Variabili d'ambiente per Android e Flutter
ENV ANDROID_HOME=/home/vscode/android-sdk
ENV FLUTTER_HOME=/home/vscode/flutter
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$FLUTTER_HOME/bin

# 4. Scarica e installa i Command Line Tools di Android (SDK)
RUN mkdir -p $ANDROID_HOME/cmdline-tools && \
    curl -o cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip && \
    unzip cmdline-tools.zip -d $ANDROID_HOME/cmdline-tools && \
    mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest && \
    rm cmdline-tools.zip

# 5. Accetta le licenze Android e installa i componenti minimi per buildare l'APK
RUN yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# 6. Scarica e configura Flutter (canale stable)
RUN git clone https://github.com/flutter/flutter.git -b stable $FLUTTER_HOME

# 7. Configura Flutter per accettare il path SDK Android e abilita il supporto Android
RUN flutter config --android-sdk $ANDROID_HOME && \
    flutter doctor --android-licenses && \
    flutter precache --android
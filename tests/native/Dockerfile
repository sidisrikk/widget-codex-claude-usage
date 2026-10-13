FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential qtbase5-dev qtdeclarative5-dev qtdeclarative5-dev-tools \
    qml-module-qttest qml-module-qtquick2 qml-module-qtquick-layouts \
    qml-module-qtquick-controls2 qml-module-org-kde-kirigami2 \
    plasma-framework libkf5i18n-dev python3 dbus-x11 \
    && rm -rf /var/lib/apt/lists/*
# The executable data engine belongs to workspace, not plasma-framework.
RUN apt-get update && apt-get install -y --no-install-recommends plasma-workspace \
    && rm -rf /var/lib/apt/lists/*
COPY . /opt/native
RUN cd /opt/native && /usr/lib/qt5/bin/qmake native.pro && make -j2
ENTRYPOINT ["/bin/bash", "/opt/native/check.sh"]

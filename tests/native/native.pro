QT += quick qml testlib
CONFIG += c++11 qmltestcase
SOURCES += runner.cpp
INCLUDEPATH += /usr/include/KF5/KI18n
LIBS += -lKF5I18n
TARGET = native-smoke

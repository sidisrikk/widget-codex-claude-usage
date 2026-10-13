#include <QtQuickTest>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQmlComponent>
#include <QQmlPropertyMap>
#include <KLocalizedContext>
#include <KLocalizedString>
#include <QQmlError>

// Only the shell-owned attached object is replaced. Core, DataSource, controls,
// layouts, Canvas and Kirigami are the installed Qt5/KF5 implementations.
class Shell : public QObject {
    Q_OBJECT
    Q_PROPERTY(QQmlPropertyMap* configuration READ configuration CONSTANT)
    Q_PROPERTY(QVariant icon MEMBER icon)
    Q_PROPERTY(QString toolTipMainText MEMBER toolTipMainText)
    Q_PROPERTY(QString toolTipSubText MEMBER toolTipSubText)
    Q_PROPERTY(QQmlComponent* compactRepresentation MEMBER compactRepresentation)
    Q_PROPERTY(QQmlComponent* fullRepresentation MEMBER fullRepresentation)
    Q_PROPERTY(int formFactor MEMBER formFactor NOTIFY changed)
    Q_PROPERTY(bool expanded MEMBER expanded NOTIFY changed)
public:
    explicit Shell(QObject *parent = nullptr) : QObject(parent) {}
    QQmlPropertyMap *configuration() { return sharedConfig; }
    static Shell *qmlAttachedProperties(QObject *object) { return new Shell(object); }
    Q_INVOKABLE void setAction(const QString &, const QString &, const QString &) {}
    static QQmlPropertyMap *sharedConfig;
    QVariant icon;
    QString toolTipMainText, toolTipSubText;
    QQmlComponent *compactRepresentation = nullptr, *fullRepresentation = nullptr;
    int formFactor = 2;
    bool expanded = false;
signals:
    void changed();
};
QQmlPropertyMap *Shell::sharedConfig = nullptr;
QML_DECLARE_TYPEINFO(Shell, QML_HAS_ATTACHED_PROPERTIES)

class Setup : public QObject {
    Q_OBJECT
    QStringList errors;
public:
    Q_INVOKABLE QStringList warnings() const { return errors; }
public slots:
    void applicationAvailable() {
        KLocalizedString::setApplicationDomain("codex-usage-native-test");
    }
    void qmlEngineAvailable(QQmlEngine *engine) {
        Shell::sharedConfig = new QQmlPropertyMap(engine);
        Shell::sharedConfig->insert("refreshInterval", 600);
        Shell::sharedConfig->insert("showPercentageLeft", true);
        Shell::sharedConfig->insert("warningThreshold", 20);
        qmlRegisterUncreatableType<Shell>("org.kde.plasma.plasmoid", 2, 0, "Plasmoid", "Attached shell fixture only");
        engine->rootContext()->setContextObject(new KLocalizedContext(engine));
        engine->rootContext()->setContextProperty("nativeDiagnostics", this);
        connect(engine, &QQmlEngine::warnings, this, [this](const QList<QQmlError> &warnings) {
            for (const auto &warning : warnings) errors.append(warning.toString());
        });
    }
};
QUICK_TEST_MAIN_WITH_SETUP(native, Setup)
#include "runner.moc"

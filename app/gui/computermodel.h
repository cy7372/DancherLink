#include "backend/computermanager.h"
#include "streaming/session.h"
#include "utils/latencymeasurer.h"

#include <QAbstractListModel>
#include <QRunnable>

class ComputerModel : public QAbstractListModel
{
    Q_OBJECT

    Q_PROPERTY(int networkLatencyMs READ networkLatencyMs NOTIFY networkLatencyChanged)
    Q_PROPERTY(QString networkQualityString READ networkQualityString NOTIFY networkLatencyChanged)

    enum Roles
    {
        NameRole = Qt::UserRole,
        OnlineRole,
        PairedRole,
        BusyRole,
        WakeableRole,
        StatusUnknownRole,
        ServerSupportedRole,
        DetailsRole
    };

public:
    explicit ComputerModel(QObject* object = nullptr);
    ~ComputerModel();

    // Must be called before any QAbstractListModel functions
    Q_INVOKABLE void initialize(ComputerManager* computerManager);

    QVariant data(const QModelIndex &index, int role) const override;

    int rowCount(const QModelIndex &parent) const override;

    virtual QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void deleteComputer(int computerIndex);

    Q_INVOKABLE QString generatePinString();

    Q_INVOKABLE void pairComputer(int computerIndex, QString pin);

    Q_INVOKABLE void cancelPairing();

    Q_INVOKABLE void testConnectionForComputer(int computerIndex);

    Q_INVOKABLE void wakeComputer(int computerIndex);

    Q_INVOKABLE void renameComputer(int computerIndex, QString name);

    Q_INVOKABLE Session* createSessionForCurrentGame(int computerIndex);

    // Network latency measurement for selected computer
    Q_INVOKABLE void startLatencyMeasurement(int computerIndex);
    Q_INVOKABLE void stopLatencyMeasurement();

    int networkLatencyMs() const;
    QString networkQualityString() const;

signals:
    void pairingCompleted(QVariant error);
    void connectionTestCompleted(int result, QString blockedPorts);
    void networkLatencyChanged(int rttMs);

private slots:
    void handleComputerStateChanged(NvComputer* computer);
    void handlePairingCompleted(NvComputer* computer, QString error);
    void handleLatencyChanged(int rttMs);

private:
    QVector<NvComputer*> m_Computers;
    ComputerManager* m_ComputerManager;
    LatencyMeasurer* m_LatencyMeasurer;
    NvComputer* m_MeasuringComputer = nullptr;  // Currently selected computer for latency display
    int m_MeasuringComputerIndex = -1;  // Index of computer we want to measure (-1 means none)
};

class DeferredTestConnectionTask : public QObject, public QRunnable
{
    Q_OBJECT
public:
    void run() override
    {
        unsigned int portTestResult = LiTestClientConnectivity("qt.conntest.moonlight-stream.org", 443, ML_PORT_FLAG_ALL);
        if (portTestResult == ML_TEST_RESULT_INCONCLUSIVE) {
            emit connectionTestCompleted(-1, QString());
        }
        else {
            char blockedPorts[512];
            LiStringifyPortFlags(portTestResult, "\n", blockedPorts, sizeof(blockedPorts));
            emit connectionTestCompleted(portTestResult, QString(blockedPorts));
        }
    }

signals:
    void connectionTestCompleted(int result, QString blockedPorts);
};

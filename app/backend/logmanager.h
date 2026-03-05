#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QTextStream>
#include <QThreadPool>
#include <QMutex>
#include <QFile>
#include <QRegularExpression>
#include <QAtomicInt>

#if defined(Q_OS_WIN32)
// Log to file or console dynamically for Windows builds
#define LOG_TO_FILE
#elif !defined(QT_DEBUG) && defined(Q_OS_DARWIN)
// Log to file for release Mac builds
#define LOG_TO_FILE
#else
// Log to console for debug Mac builds
#endif

#include "SDL_compat.h"

class LogManager : public QObject
{
    Q_OBJECT

public:
    static LogManager* instance();

    void initialize(bool suppressVerboseOutput);
    void shutdown();

    void setSuppressVerboseOutput(bool suppress);
    bool isVerboseOutputSuppressed() const;

    void enterAsyncLoggingMode();
    void exitAsyncLoggingMode();
    bool isAsyncLoggingEnabled() const;

    // Session-specific logging
    void startSessionLog(const QString& serverName = QString());
    void endSessionLog();

    void writeLogSync(const QString& message);

    // Logging handlers
    static void sdlLogToDiskHandler(void* userdata, int category, SDL_LogPriority priority, const char* message);
    static void qtLogToDiskHandler(QtMsgType type, const QMessageLogContext& context, const QString& msg);
#ifdef HAVE_FFMPEG
    static void ffmpegLogToDiskHandler(void* ptr, int level, const char* fmt, va_list vl);
#endif

private:
    explicit LogManager(QObject* parent = nullptr);
    ~LogManager();

    void logToLoggerStream(QString& message);

    static LogManager* s_Instance;
    
    QElapsedTimer m_LoggerTime;
    QTextStream m_LoggerStream;
    QThreadPool m_LoggerThread;
    QMutex m_SyncLoggerMutex;
    bool m_SuppressVerboseOutput;
    
    QRegularExpression m_RikeyRegex;
    QRegularExpression m_RikeyIdRegex;

#ifdef LOG_TO_FILE
    QFile* m_LoggerFile;
    QAtomicInteger<uint64_t> m_LogBytesWritten;
#endif

    QAtomicInt m_AsyncLoggingEnabled;
};

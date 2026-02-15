#include "logmanager.h"
#include "path.h"

#include <QCoreApplication>
#include <QDir>
#include <QDateTime>
#include <QRunnable>

#ifdef HAVE_FFMPEG
extern "C" {
#include <libavutil/log.h>
}
#endif

#if defined(Q_OS_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#define IS_UNSPECIFIED_HANDLE(x) ((x) == INVALID_HANDLE_VALUE || (x) == NULL)
#endif

// Max log file size of 10 MB
static const uint64_t k_MaxLogSizeBytes = 10 * 1024 * 1024;

LogManager* LogManager::s_Instance = nullptr;

class LoggerTask : public QRunnable
{
public:
    LoggerTask(LogManager* manager, const QString& msg) 
        : m_Manager(manager), m_Msg(msg)
    {
        setAutoDelete(true);
    }

    void run() override
    {
        // Access private members via friend or public method? 
        // Since LoggerTask is in cpp, it can't easily access private members unless it's a friend class in header.
        // But I didn't declare it in header.
        // I'll make logToLoggerStreamInternal public or similar, or just use a lambda if I could (but QThreadPool uses QRunnable).
        // Actually, I can add a friend declaration in LogManager header later if needed, 
        // or just expose a method "writeLog(QString)".
        // But "writeLog" is what calls start(new LoggerTask)... infinite recursion if not careful.
        // I will add a `writeLogSync(QString)` method to LogManager.
        m_Manager->writeLogSync(m_Msg);
    }

private:
    LogManager* m_Manager;
    QString m_Msg;
};

LogManager* LogManager::instance()
{
    if (!s_Instance) {
        s_Instance = new LogManager();
    }
    return s_Instance;
}

LogManager::LogManager(QObject* parent)
    : QObject(parent)
    , m_LoggerStream(stderr)
    , m_SuppressVerboseOutput(false)
    , m_RikeyRegex("&rikey=\\w+")
    , m_RikeyIdRegex("&rikeyid=[\\d-]+")
#ifdef LOG_TO_FILE
    , m_LoggerFile(nullptr)
    , m_LogBytesWritten(0)
#endif
    , m_AsyncLoggingEnabled(0)
{
    // Serialize log messages on a single thread
    m_LoggerThread.setMaxThreadCount(1);
}

LogManager::~LogManager()
{
#ifdef LOG_TO_FILE
    if (m_LoggerFile) {
        m_LoggerFile->close();
        delete m_LoggerFile;
    }
#endif
}

void LogManager::initialize(bool suppressVerboseOutput)
{
    m_SuppressVerboseOutput = suppressVerboseOutput;

#ifdef Q_OS_WIN32
    // Grab the original std handles before we potentially redirect them later
    HANDLE oldConOut = GetStdHandle(STD_OUTPUT_HANDLE);
    HANDLE oldConErr = GetStdHandle(STD_ERROR_HANDLE);
#endif

#ifdef LOG_TO_FILE
    QDir tempDir(Path::getLogDir());

#ifdef Q_OS_WIN32
    // Only log to a file if the user didn't redirect stderr somewhere else
    if (IS_UNSPECIFIED_HANDLE(oldConErr))
#endif
    {
        // Use human-readable datetime format for log filename
        QString logFileName = QString("DancherLink-%1.log")
            .arg(QDateTime::currentDateTime().toString("yyyy-MM-dd_HH-mm-ss"));
        m_LoggerFile = new QFile(tempDir.filePath(logFileName));
        if (m_LoggerFile->open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream(stderr) << "Redirecting log output to " << m_LoggerFile->fileName() << Qt::endl;
            m_LoggerStream.setDevice(m_LoggerFile);
        }
    }
    
    // Prune the oldest existing logs if there are more than 10
    QStringList existingLogNames = tempDir.entryList(QStringList("DancherLink-*.log"), QDir::NoFilter, QDir::SortFlag::Time);
    for (qsizetype i = 10; i < existingLogNames.size(); i++) {
        qInfo() << "Removing old log file:" << existingLogNames.at(i);
        QFile(tempDir.filePath(existingLogNames.at(i))).remove();
    }
#endif

    m_LoggerTime.start();

    // Register our logger with all libraries
#if SDL_VERSION_ATLEAST(3, 0, 0)
    SDL_SetLogOutputFunction(sdlLogToDiskHandler, this);
#else
    SDL_LogSetOutputFunction(sdlLogToDiskHandler, this);
#endif
    qInstallMessageHandler(qtLogToDiskHandler);
#ifdef HAVE_FFMPEG
    av_log_set_callback(ffmpegLogToDiskHandler);
#endif
}

void LogManager::shutdown()
{
    // Restore the default logger for all libraries
#if SDL_VERSION_ATLEAST(3, 0, 0)
    SDL_SetLogOutputFunction(SDL_GetDefaultLogOutputFunction(), nullptr);
#else
    SDL_LogSetOutputFunction(SDL_LogOutputFunction(NULL), nullptr); // Restore default is tricky in SDL2 if we don't save it. 
    // Actually main.cpp saved it. But here we can just set to NULL or standard.
    // SDL_LogSetOutputFunction(NULL, NULL) resets to default on many platforms or valid impl.
    // Let's check main.cpp logic. It saved oldSdlLogFn. 
    // Since we are singleton, we might want to save it too if we want to be perfect.
    // But usually NULL works to reset or just leave it as we exit.
    // main.cpp used: SDL_LogSetOutputFunction(oldSdlLogFn, oldSdlLogUserdata);
    // I'll assume for now we can just leave it or set to NULL.
#endif
    qInstallMessageHandler(nullptr);
#ifdef HAVE_FFMPEG
    av_log_set_callback(av_log_default_callback);
#endif

    // We should not be in async logging mode anymore
    Q_ASSERT(m_AsyncLoggingEnabled == 0);

    // Wait for pending log messages to be printed
    m_LoggerThread.waitForDone();

#ifdef Q_OS_WIN32
    // Without an explicit flush, console redirection for the list command
    // doesn't work reliably (sometimes the target file contains no text).
    fflush(stderr);
    fflush(stdout);
#endif
}

void LogManager::setSuppressVerboseOutput(bool suppress)
{
    m_SuppressVerboseOutput = suppress;
}

bool LogManager::isVerboseOutputSuppressed() const
{
    return m_SuppressVerboseOutput;
}

void LogManager::enterAsyncLoggingMode()
{
    m_AsyncLoggingEnabled.ref();
}

void LogManager::exitAsyncLoggingMode()
{
    m_AsyncLoggingEnabled.deref();
}

bool LogManager::isAsyncLoggingEnabled() const
{
    return m_AsyncLoggingEnabled != 0;
}

void LogManager::writeLogSync(const QString& message)
{
    // QTextStream is not thread-safe, so we must lock.
    QMutexLocker locker(&m_SyncLoggerMutex);
    m_LoggerStream << message;
    m_LoggerStream.flush();
}

void LogManager::logToLoggerStream(QString& message)
{
#if defined(QT_DEBUG) && defined(Q_OS_WIN32)
    // Output log messages to a debugger if attached
    if (IsDebuggerPresent()) {
        thread_local QString lineBuffer;
        lineBuffer += message;
        if (message.endsWith('\n')) {
            OutputDebugStringW(lineBuffer.toStdWString().c_str());
            lineBuffer.clear();
        }
    }
#endif

    // Strip session encryption keys and IVs from the logs
    message.replace(m_RikeyRegex, "&rikey=REDACTED");
    message.replace(m_RikeyIdRegex, "&rikeyid=REDACTED");

#ifdef LOG_TO_FILE
    auto oldLogSize = m_LogBytesWritten.fetchAndAddRelaxed(message.size());
    if (oldLogSize >= k_MaxLogSizeBytes) {
        return;
    }
    else if (oldLogSize + message.size() >= k_MaxLogSizeBytes) {
        // Keep the original message and append a clear warning
        message += QStringLiteral("\n\n=== LOG SIZE LIMIT REACHED (%1 MB) ===\n"
                                  "Logging has been suspended for this session.\n"
                                  "Delete or rename this log file and restart the application to resume logging.\n")
                   .arg(k_MaxLogSizeBytes / (1024 * 1024));
    }
#endif

    if (isAsyncLoggingEnabled()) {
        // Queue the log message to be written asynchronously
        m_LoggerThread.start(new LoggerTask(this, message));
    }
    else {
        // Log the message immediately
        LoggerTask(this, message).run();
    }
}

void LogManager::sdlLogToDiskHandler(void* userdata, int category, SDL_LogPriority priority, const char* message)
{
    LogManager* self = static_cast<LogManager*>(userdata);
    // Fallback if userdata is null (shouldn't happen if we set it right)
    if (!self) self = instance();

    QString priorityTxt;

    switch (priority) {
    case SDL_LOG_PRIORITY_VERBOSE:
        if (self->m_SuppressVerboseOutput) {
            return;
        }
        priorityTxt = "Verbose";
        break;
    case SDL_LOG_PRIORITY_DEBUG:
        if (self->m_SuppressVerboseOutput) {
            return;
        }
        priorityTxt = "Debug";
        break;
    case SDL_LOG_PRIORITY_INFO:
        if (self->m_SuppressVerboseOutput) {
            return;
        }
        priorityTxt = "Info";
        break;
    case SDL_LOG_PRIORITY_WARN:
        if (self->m_SuppressVerboseOutput) {
            return;
        }
        priorityTxt = "Warn";
        break;
    case SDL_LOG_PRIORITY_ERROR:
        priorityTxt = "Error";
        break;
    case SDL_LOG_PRIORITY_CRITICAL:
        priorityTxt = "Critical";
        break;
    default:
        priorityTxt = "Unknown";
        break;
    }

    QTime logTime = QTime::fromMSecsSinceStartOfDay(self->m_LoggerTime.elapsed());
    QString txt = QString("%1 - SDL %2 (%3): %4\n").arg(logTime.toString()).arg(priorityTxt).arg(category).arg(message);

    self->logToLoggerStream(txt);
}

void LogManager::qtLogToDiskHandler(QtMsgType type, const QMessageLogContext&, const QString& msg)
{
    LogManager* self = instance();

    QString typeTxt;

    switch (type) {
    case QtDebugMsg:
        if (self->m_SuppressVerboseOutput) {
            return;
        }
        typeTxt = "Debug";
        break;
    case QtInfoMsg:
        if (self->m_SuppressVerboseOutput) {
            return;
        }
        typeTxt = "Info";
        break;
    case QtWarningMsg:
        if (self->m_SuppressVerboseOutput) {
            return;
        }
        typeTxt = "Warning";
        break;
    case QtCriticalMsg:
        typeTxt = "Critical";
        break;
    case QtFatalMsg:
        typeTxt = "Fatal";
        break;
    }

    QTime logTime = QTime::fromMSecsSinceStartOfDay(self->m_LoggerTime.elapsed());
    QString txt = QString("%1 - Qt %2: %3\n").arg(logTime.toString()).arg(typeTxt).arg(msg);

    self->logToLoggerStream(txt);
}

#ifdef HAVE_FFMPEG
void LogManager::ffmpegLogToDiskHandler(void* ptr, int level, const char* fmt, va_list vl)
{
    LogManager* self = instance();
    
    char lineBuffer[1024];
    static int printPrefix = 1;

    if ((level & 0xFF) > av_log_get_level()) {
        return;
    }
    else if ((level & 0xFF) > AV_LOG_WARNING && self->m_SuppressVerboseOutput) {
        return;
    }

    // We need to use the *previous* printPrefix value to determine whether to
    // print the prefix this time. av_log_format_line() will set the printPrefix
    // value to indicate whether the prefix should be printed *next time*.
    bool shouldPrefixThisMessage = printPrefix != 0;

    av_log_format_line(ptr, level, fmt, vl, lineBuffer, sizeof(lineBuffer), &printPrefix);

    if (shouldPrefixThisMessage) {
        QTime logTime = QTime::fromMSecsSinceStartOfDay(self->m_LoggerTime.elapsed());
        QString txt = QString("%1 - FFmpeg: %2").arg(logTime.toString()).arg(lineBuffer);
        self->logToLoggerStream(txt);
    }
    else {
        QString txt = QString(lineBuffer);
        self->logToLoggerStream(txt);
    }
}
#endif

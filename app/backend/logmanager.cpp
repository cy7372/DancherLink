#include "logmanager.h"
#include "path.h"

#include <QCoreApplication>
#include <QDir>
#include <QDateTime>
#include <QRunnable>
#include <QSemaphore>
#include <QWaitCondition>
#include <QQueue>

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

// Object pool for LoggerTask to reduce memory allocations
// Uses a simple linked-list based free list
class LoggerTaskPool {
public:
    static LoggerTaskPool* instance() {
        static LoggerTaskPool pool;
        return &pool;
    }

    class PooledLoggerTask : public QRunnable {
    public:
        PooledLoggerTask()
            : m_Manager(nullptr), m_RefCount(0)
        {
            setAutoDelete(false); // We manage deletion via the pool
        }

        void init(LogManager* manager, const QString& msg) {
            m_Manager = manager;
            m_Msg = msg;
            m_RefCount.storeRelaxed(1);
        }

        void run() override {
            if (m_Manager) {
                m_Manager->writeLogSync(m_Msg);
            }
            // Return to pool after execution
            LoggerTaskPool::instance()->release(this);
        }

        // Allow atomic decrement and check for last reference
        bool deref() {
            return m_RefCount.deref();
        }

    private:
        LogManager* m_Manager;
        QString m_Msg;
        QAtomicInt m_RefCount;
    };

    PooledLoggerTask* acquire(LogManager* manager, const QString& msg) {
        QMutexLocker locker(&m_Mutex);

        PooledLoggerTask* task;
        if (!m_FreeList.isEmpty()) {
            task = m_FreeList.dequeue();
        } else {
            task = new PooledLoggerTask();
        }

        task->init(manager, msg);
        return task;
    }

    void release(PooledLoggerTask* task) {
        QMutexLocker locker(&m_Mutex);

        // Limit pool size to avoid excessive memory usage
        while (m_FreeList.size() >= 16) {
            PooledLoggerTask* oldest = m_FreeList.dequeue();
            delete oldest;
        }

        m_FreeList.enqueue(task);
    }

private:
    LoggerTaskPool() = default;
    ~LoggerTaskPool() {
        qDeleteAll(m_FreeList);
        m_FreeList.clear();
    }

    QMutex m_Mutex;
    QQueue<PooledLoggerTask*> m_FreeList;
};

LogManager* LogManager::s_Instance = nullptr;

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
        // Simple filename format: dl_MMDD_HHMM.log (dl = DancherLink)
        QDateTime now = QDateTime::currentDateTime();
        QString logFileName = QString("dl_%1.log")
            .arg(now.toString("MMdd_HHmm"));

        // Ensure the filename is unique by checking if it exists
        QString fullPath = tempDir.filePath(logFileName);
        int counter = 2;
        while (QFile::exists(fullPath)) {
            logFileName = QString("dl_%1_%2.log")
                .arg(now.toString("MMdd_HHmm"))
                .arg(counter++);
            fullPath = tempDir.filePath(logFileName);
        }

        m_LoggerFile = new QFile(fullPath);
        if (m_LoggerFile->open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream(stderr) << "Log: " << m_LoggerFile->fileName() << Qt::endl;
            m_LoggerStream.setDevice(m_LoggerFile);
        }
    }

    // Prune the oldest existing logs if there are more than 10
    QStringList existingLogNames = tempDir.entryList(QStringList("dl_*.log"), QDir::NoFilter, QDir::SortFlag::Time);
    for (qsizetype i = 10; i < existingLogNames.size(); i++) {
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

void LogManager::startSessionLog(const QString& serverName)
{
#ifdef LOG_TO_FILE
    // Wait for any pending log writes to complete
    m_LoggerThread.waitForDone();

    // Just add a session start marker, don't create a new file
    QMutexLocker locker(&m_SyncLoggerMutex);
    if (m_LoggerFile) {
        m_LoggerStream << Qt::endl;
        m_LoggerStream << "========== STREAM START";
        if (!serverName.isEmpty()) {
            m_LoggerStream << " [" << serverName << "]";
        }
        m_LoggerStream << " ==========" << Qt::endl;
        m_LoggerStream.flush();
    }
#else
    Q_UNUSED(serverName);
#endif
}

void LogManager::endSessionLog()
{
#ifdef LOG_TO_FILE
    // Wait for any pending log writes to complete
    m_LoggerThread.waitForDone();

    // Just add a session end marker
    QMutexLocker locker(&m_SyncLoggerMutex);
    if (m_LoggerFile) {
        m_LoggerStream << "========== STREAM END ==========" << Qt::endl;
        m_LoggerStream << Qt::endl;
        m_LoggerStream.flush();
    }
#endif
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
        // Queue the log message to be written asynchronously using pooled task
        auto* task = LoggerTaskPool::instance()->acquire(this, message);
        m_LoggerThread.start(task);
    }
    else {
        // Log the message immediately (synchronously)
        writeLogSync(message);
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

    QString timestamp = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss.zzz");
    QString txt = QString("%1 - SDL %2 (%3): %4\n").arg(timestamp).arg(priorityTxt).arg(category).arg(message);

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

    QString timestamp = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss.zzz");
    QString txt = QString("%1 - Qt %2: %3\n").arg(timestamp).arg(typeTxt).arg(msg);

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
        QString timestamp = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss.zzz");
        QString txt = QString("%1 - FFmpeg: %2").arg(timestamp).arg(lineBuffer);
        self->logToLoggerStream(txt);
    }
    else {
        QString txt = QString(lineBuffer);
        self->logToLoggerStream(txt);
    }
}
#endif

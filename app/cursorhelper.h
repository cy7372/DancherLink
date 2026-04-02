#pragma once

#include <QObject>
#include <QCursor>
#include <QPointF>

// Minimal helper to expose QCursor::pos() to QML for hover detection.
// No Q_OBJECT needed — Q_INVOKABLE works via the base QObject's meta-object.
class CursorHelper : public QObject
{
public:
    explicit CursorHelper(QObject* parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE QPointF cursorPos() const { return QCursor::pos(); }
};

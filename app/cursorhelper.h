#pragma once

#include <QObject>
#include <QCursor>
#include <QPointF>

class CursorHelper : public QObject
{
    Q_OBJECT
public:
    explicit CursorHelper(QObject* parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE QPointF cursorPos() const { return QCursor::pos(); }
};

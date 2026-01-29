/****************************************************************************
** Meta object code from reading C++ file 'browser_p.h'
**
** Created by: The Qt Meta Object Compiler version 69 (Qt 6.10.1)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../qmdnsengine/src/src/browser_p.h"
#include <QtCore/qmetatype.h>

#include <QtCore/qtmochelpers.h>

#include <memory>


#include <QtCore/qxptype_traits.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'browser_p.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 69
#error "This file was generated using the moc from 6.10.1. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {
struct qt_meta_tag_ZN11QMdnsEngine14BrowserPrivateE_t {};
} // unnamed namespace

template <> constexpr inline auto QMdnsEngine::BrowserPrivate::qt_create_metaobjectdata<qt_meta_tag_ZN11QMdnsEngine14BrowserPrivateE_t>()
{
    namespace QMC = QtMocConstants;
    QtMocHelpers::StringRefStorage qt_stringData {
        "QMdnsEngine::BrowserPrivate",
        "onMessageReceived",
        "",
        "Message",
        "message",
        "onShouldQuery",
        "Record",
        "record",
        "onRecordExpired",
        "onQueryTimeout",
        "onServiceTimeout"
    };

    QtMocHelpers::UintData qt_methods {
        // Slot 'onMessageReceived'
        QtMocHelpers::SlotData<void(const Message &)>(1, 2, QMC::AccessPrivate, QMetaType::Void, {{
            { 0x80000000 | 3, 4 },
        }}),
        // Slot 'onShouldQuery'
        QtMocHelpers::SlotData<void(const Record &)>(5, 2, QMC::AccessPrivate, QMetaType::Void, {{
            { 0x80000000 | 6, 7 },
        }}),
        // Slot 'onRecordExpired'
        QtMocHelpers::SlotData<void(const Record &)>(8, 2, QMC::AccessPrivate, QMetaType::Void, {{
            { 0x80000000 | 6, 7 },
        }}),
        // Slot 'onQueryTimeout'
        QtMocHelpers::SlotData<void()>(9, 2, QMC::AccessPrivate, QMetaType::Void),
        // Slot 'onServiceTimeout'
        QtMocHelpers::SlotData<void()>(10, 2, QMC::AccessPrivate, QMetaType::Void),
    };
    QtMocHelpers::UintData qt_properties {
    };
    QtMocHelpers::UintData qt_enums {
    };
    return QtMocHelpers::metaObjectData<BrowserPrivate, qt_meta_tag_ZN11QMdnsEngine14BrowserPrivateE_t>(QMC::MetaObjectFlag{}, qt_stringData,
            qt_methods, qt_properties, qt_enums);
}
Q_CONSTINIT const QMetaObject QMdnsEngine::BrowserPrivate::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN11QMdnsEngine14BrowserPrivateE_t>.stringdata,
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN11QMdnsEngine14BrowserPrivateE_t>.data,
    qt_static_metacall,
    nullptr,
    qt_staticMetaObjectRelocatingContent<qt_meta_tag_ZN11QMdnsEngine14BrowserPrivateE_t>.metaTypes,
    nullptr
} };

void QMdnsEngine::BrowserPrivate::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    auto *_t = static_cast<BrowserPrivate *>(_o);
    if (_c == QMetaObject::InvokeMetaMethod) {
        switch (_id) {
        case 0: _t->onMessageReceived((*reinterpret_cast<std::add_pointer_t<Message>>(_a[1]))); break;
        case 1: _t->onShouldQuery((*reinterpret_cast<std::add_pointer_t<Record>>(_a[1]))); break;
        case 2: _t->onRecordExpired((*reinterpret_cast<std::add_pointer_t<Record>>(_a[1]))); break;
        case 3: _t->onQueryTimeout(); break;
        case 4: _t->onServiceTimeout(); break;
        default: ;
        }
    }
}

const QMetaObject *QMdnsEngine::BrowserPrivate::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *QMdnsEngine::BrowserPrivate::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_staticMetaObjectStaticContent<qt_meta_tag_ZN11QMdnsEngine14BrowserPrivateE_t>.strings))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int QMdnsEngine::BrowserPrivate::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 5)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 5;
    }
    if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 5)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 5;
    }
    return _id;
}
QT_WARNING_POP

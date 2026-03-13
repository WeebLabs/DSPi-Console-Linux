/****************************************************************************
** Meta object code from reading C++ file 'BodePlotItem.h'
**
** Created by: The Qt Meta Object Compiler version 67 (Qt 5.15.17)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <memory>
#include "../../../src/BodePlotItem.h"
#include <QtCore/qbytearray.h>
#include <QtCore/qmetatype.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'BodePlotItem.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 67
#error "This file was generated using the moc from 5.15.17. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

QT_BEGIN_MOC_NAMESPACE
QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
struct qt_meta_stringdata_BodePlotItem_t {
    QByteArrayData data[16];
    char stringdata0[157];
};
#define QT_MOC_LITERAL(idx, ofs, len) \
    Q_STATIC_BYTE_ARRAY_DATA_HEADER_INITIALIZER_WITH_OFFSET(len, \
    qptrdiff(offsetof(qt_meta_stringdata_BodePlotItem_t, stringdata0) + ofs \
        - idx * sizeof(QByteArrayData)) \
    )
static const qt_meta_stringdata_BodePlotItem_t qt_meta_stringdata_BodePlotItem = {
    {
QT_MOC_LITERAL(0, 0, 12), // "BodePlotItem"
QT_MOC_LITERAL(1, 13, 15), // "settingsChanged"
QT_MOC_LITERAL(2, 29, 0), // ""
QT_MOC_LITERAL(3, 30, 9), // "setBridge"
QT_MOC_LITERAL(4, 40, 6), // "bridge"
QT_MOC_LITERAL(5, 47, 7), // "refresh"
QT_MOC_LITERAL(6, 55, 5), // "dbTop"
QT_MOC_LITERAL(7, 61, 8), // "dbBottom"
QT_MOC_LITERAL(8, 70, 7), // "minFreq"
QT_MOC_LITERAL(9, 78, 7), // "maxFreq"
QT_MOC_LITERAL(10, 86, 8), // "showGlow"
QT_MOC_LITERAL(11, 95, 12), // "showFreqGrid"
QT_MOC_LITERAL(12, 108, 10), // "showDbGrid"
QT_MOC_LITERAL(13, 119, 14), // "showFreqLabels"
QT_MOC_LITERAL(14, 134, 12), // "showDbLabels"
QT_MOC_LITERAL(15, 147, 9) // "lineWidth"

    },
    "BodePlotItem\0settingsChanged\0\0setBridge\0"
    "bridge\0refresh\0dbTop\0dbBottom\0minFreq\0"
    "maxFreq\0showGlow\0showFreqGrid\0showDbGrid\0"
    "showFreqLabels\0showDbLabels\0lineWidth"
};
#undef QT_MOC_LITERAL

static const uint qt_meta_data_BodePlotItem[] = {

 // content:
       8,       // revision
       0,       // classname
       0,    0, // classinfo
       3,   14, // methods
      10,   34, // properties
       0,    0, // enums/sets
       0,    0, // constructors
       0,       // flags
       1,       // signalCount

 // signals: name, argc, parameters, tag, flags
       1,    0,   29,    2, 0x06 /* Public */,

 // methods: name, argc, parameters, tag, flags
       3,    1,   30,    2, 0x02 /* Public */,
       5,    0,   33,    2, 0x02 /* Public */,

 // signals: parameters
    QMetaType::Void,

 // methods: parameters
    QMetaType::Void, QMetaType::QObjectStar,    4,
    QMetaType::Void,

 // properties: name, type, flags
       6, QMetaType::Float, 0x00495103,
       7, QMetaType::Float, 0x00495103,
       8, QMetaType::Float, 0x00495103,
       9, QMetaType::Float, 0x00495103,
      10, QMetaType::Bool, 0x00495103,
      11, QMetaType::Bool, 0x00495103,
      12, QMetaType::Bool, 0x00495103,
      13, QMetaType::Bool, 0x00495103,
      14, QMetaType::Bool, 0x00495103,
      15, QMetaType::Float, 0x00495103,

 // properties: notify_signal_id
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       0,

       0        // eod
};

void BodePlotItem::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    if (_c == QMetaObject::InvokeMetaMethod) {
        auto *_t = static_cast<BodePlotItem *>(_o);
        (void)_t;
        switch (_id) {
        case 0: _t->settingsChanged(); break;
        case 1: _t->setBridge((*reinterpret_cast< QObject*(*)>(_a[1]))); break;
        case 2: _t->refresh(); break;
        default: ;
        }
    } else if (_c == QMetaObject::IndexOfMethod) {
        int *result = reinterpret_cast<int *>(_a[0]);
        {
            using _t = void (BodePlotItem::*)();
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&BodePlotItem::settingsChanged)) {
                *result = 0;
                return;
            }
        }
    }
#ifndef QT_NO_PROPERTIES
    else if (_c == QMetaObject::ReadProperty) {
        auto *_t = static_cast<BodePlotItem *>(_o);
        (void)_t;
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast< float*>(_v) = _t->dbTop(); break;
        case 1: *reinterpret_cast< float*>(_v) = _t->dbBottom(); break;
        case 2: *reinterpret_cast< float*>(_v) = _t->minFreq(); break;
        case 3: *reinterpret_cast< float*>(_v) = _t->maxFreq(); break;
        case 4: *reinterpret_cast< bool*>(_v) = _t->showGlow(); break;
        case 5: *reinterpret_cast< bool*>(_v) = _t->showFreqGrid(); break;
        case 6: *reinterpret_cast< bool*>(_v) = _t->showDbGrid(); break;
        case 7: *reinterpret_cast< bool*>(_v) = _t->showFreqLabels(); break;
        case 8: *reinterpret_cast< bool*>(_v) = _t->showDbLabels(); break;
        case 9: *reinterpret_cast< float*>(_v) = _t->lineWidth(); break;
        default: break;
        }
    } else if (_c == QMetaObject::WriteProperty) {
        auto *_t = static_cast<BodePlotItem *>(_o);
        (void)_t;
        void *_v = _a[0];
        switch (_id) {
        case 0: _t->setDbTop(*reinterpret_cast< float*>(_v)); break;
        case 1: _t->setDbBottom(*reinterpret_cast< float*>(_v)); break;
        case 2: _t->setMinFreq(*reinterpret_cast< float*>(_v)); break;
        case 3: _t->setMaxFreq(*reinterpret_cast< float*>(_v)); break;
        case 4: _t->setShowGlow(*reinterpret_cast< bool*>(_v)); break;
        case 5: _t->setShowFreqGrid(*reinterpret_cast< bool*>(_v)); break;
        case 6: _t->setShowDbGrid(*reinterpret_cast< bool*>(_v)); break;
        case 7: _t->setShowFreqLabels(*reinterpret_cast< bool*>(_v)); break;
        case 8: _t->setShowDbLabels(*reinterpret_cast< bool*>(_v)); break;
        case 9: _t->setLineWidth(*reinterpret_cast< float*>(_v)); break;
        default: break;
        }
    } else if (_c == QMetaObject::ResetProperty) {
    }
#endif // QT_NO_PROPERTIES
}

QT_INIT_METAOBJECT const QMetaObject BodePlotItem::staticMetaObject = { {
    QMetaObject::SuperData::link<QQuickPaintedItem::staticMetaObject>(),
    qt_meta_stringdata_BodePlotItem.data,
    qt_meta_data_BodePlotItem,
    qt_static_metacall,
    nullptr,
    nullptr
} };


const QMetaObject *BodePlotItem::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *BodePlotItem::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_meta_stringdata_BodePlotItem.stringdata0))
        return static_cast<void*>(this);
    return QQuickPaintedItem::qt_metacast(_clname);
}

int BodePlotItem::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QQuickPaintedItem::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 3)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 3;
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 3)
            *reinterpret_cast<int*>(_a[0]) = -1;
        _id -= 3;
    }
#ifndef QT_NO_PROPERTIES
    else if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 10;
    } else if (_c == QMetaObject::QueryPropertyDesignable) {
        _id -= 10;
    } else if (_c == QMetaObject::QueryPropertyScriptable) {
        _id -= 10;
    } else if (_c == QMetaObject::QueryPropertyStored) {
        _id -= 10;
    } else if (_c == QMetaObject::QueryPropertyEditable) {
        _id -= 10;
    } else if (_c == QMetaObject::QueryPropertyUser) {
        _id -= 10;
    }
#endif // QT_NO_PROPERTIES
    return _id;
}

// SIGNAL 0
void BodePlotItem::settingsChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 0, nullptr);
}
QT_WARNING_POP
QT_END_MOC_NAMESPACE

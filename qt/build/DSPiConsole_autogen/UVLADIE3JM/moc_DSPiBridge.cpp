/****************************************************************************
** Meta object code from reading C++ file 'DSPiBridge.h'
**
** Created by: The Qt Meta Object Compiler version 67 (Qt 5.15.17)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <memory>
#include "../../../src/DSPiBridge.h"
#include <QtCore/qbytearray.h>
#include <QtCore/qmetatype.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'DSPiBridge.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 67
#error "This file was generated using the moc from 5.15.17. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

QT_BEGIN_MOC_NAMESPACE
QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
struct qt_meta_stringdata_DSPiBridge_t {
    QByteArrayData data[121];
    char stringdata0[1420];
};
#define QT_MOC_LITERAL(idx, ofs, len) \
    Q_STATIC_BYTE_ARRAY_DATA_HEADER_INITIALIZER_WITH_OFFSET(len, \
    qptrdiff(offsetof(qt_meta_stringdata_DSPiBridge_t, stringdata0) + ofs \
        - idx * sizeof(QByteArrayData)) \
    )
static const qt_meta_stringdata_DSPiBridge_t qt_meta_stringdata_DSPiBridge = {
    {
QT_MOC_LITERAL(0, 0, 10), // "DSPiBridge"
QT_MOC_LITERAL(1, 11, 12), // "stateChanged"
QT_MOC_LITERAL(2, 24, 0), // ""
QT_MOC_LITERAL(3, 25, 13), // "statusChanged"
QT_MOC_LITERAL(4, 39, 14), // "devicesChanged"
QT_MOC_LITERAL(5, 54, 13), // "deviceArrived"
QT_MOC_LITERAL(6, 68, 6), // "serial"
QT_MOC_LITERAL(7, 75, 14), // "deviceDeparted"
QT_MOC_LITERAL(8, 90, 17), // "magnitudesChanged"
QT_MOC_LITERAL(9, 108, 10), // "pollStatus"
QT_MOC_LITERAL(10, 119, 11), // "pollHotplug"
QT_MOC_LITERAL(11, 131, 9), // "peakLevel"
QT_MOC_LITERAL(12, 141, 2), // "ch"
QT_MOC_LITERAL(13, 144, 10), // "isClipping"
QT_MOC_LITERAL(14, 155, 11), // "channelName"
QT_MOC_LITERAL(15, 167, 12), // "channelColor"
QT_MOC_LITERAL(16, 180, 17), // "channelDescriptor"
QT_MOC_LITERAL(17, 198, 10), // "filterType"
QT_MOC_LITERAL(18, 209, 4), // "band"
QT_MOC_LITERAL(19, 214, 10), // "filterFreq"
QT_MOC_LITERAL(20, 225, 10), // "filterGain"
QT_MOC_LITERAL(21, 236, 7), // "filterQ"
QT_MOC_LITERAL(22, 244, 13), // "outputEnabled"
QT_MOC_LITERAL(23, 258, 3), // "idx"
QT_MOC_LITERAL(24, 262, 11), // "outputMuted"
QT_MOC_LITERAL(25, 274, 12), // "outputGainDB"
QT_MOC_LITERAL(26, 287, 13), // "outputDelayMS"
QT_MOC_LITERAL(27, 301, 13), // "matrixRouting"
QT_MOC_LITERAL(28, 315, 5), // "input"
QT_MOC_LITERAL(29, 321, 6), // "output"
QT_MOC_LITERAL(30, 328, 10), // "matrixGain"
QT_MOC_LITERAL(31, 339, 12), // "matrixInvert"
QT_MOC_LITERAL(32, 352, 9), // "outputPin"
QT_MOC_LITERAL(33, 362, 7), // "physOut"
QT_MOC_LITERAL(34, 370, 10), // "presetName"
QT_MOC_LITERAL(35, 381, 4), // "slot"
QT_MOC_LITERAL(36, 386, 16), // "isPresetOccupied"
QT_MOC_LITERAL(37, 403, 14), // "magnitudeCurve"
QT_MOC_LITERAL(38, 418, 4), // "eqCh"
QT_MOC_LITERAL(39, 423, 9), // "setPreamp"
QT_MOC_LITERAL(40, 433, 2), // "db"
QT_MOC_LITERAL(41, 436, 18), // "sendPreampToDevice"
QT_MOC_LITERAL(42, 455, 9), // "setBypass"
QT_MOC_LITERAL(43, 465, 2), // "en"
QT_MOC_LITERAL(44, 468, 9), // "setFilter"
QT_MOC_LITERAL(45, 478, 4), // "type"
QT_MOC_LITERAL(46, 483, 4), // "freq"
QT_MOC_LITERAL(47, 488, 4), // "gain"
QT_MOC_LITERAL(48, 493, 1), // "q"
QT_MOC_LITERAL(49, 495, 11), // "setLoudness"
QT_MOC_LITERAL(50, 507, 14), // "setLoudnessRef"
QT_MOC_LITERAL(51, 522, 3), // "spl"
QT_MOC_LITERAL(52, 526, 20), // "setLoudnessIntensity"
QT_MOC_LITERAL(53, 547, 3), // "pct"
QT_MOC_LITERAL(54, 551, 12), // "setCrossfeed"
QT_MOC_LITERAL(55, 564, 18), // "setCrossfeedPreset"
QT_MOC_LITERAL(56, 583, 1), // "p"
QT_MOC_LITERAL(57, 585, 16), // "setCrossfeedFreq"
QT_MOC_LITERAL(58, 602, 16), // "setCrossfeedFeed"
QT_MOC_LITERAL(59, 619, 4), // "feed"
QT_MOC_LITERAL(60, 624, 15), // "setCrossfeedITD"
QT_MOC_LITERAL(61, 640, 14), // "setMatrixRoute"
QT_MOC_LITERAL(62, 655, 7), // "enabled"
QT_MOC_LITERAL(63, 663, 6), // "invert"
QT_MOC_LITERAL(64, 670, 15), // "setOutputEnable"
QT_MOC_LITERAL(65, 686, 13), // "setOutputGain"
QT_MOC_LITERAL(66, 700, 22), // "sendOutputGainToDevice"
QT_MOC_LITERAL(67, 723, 13), // "setOutputMute"
QT_MOC_LITERAL(68, 737, 5), // "muted"
QT_MOC_LITERAL(69, 743, 14), // "setOutputDelay"
QT_MOC_LITERAL(70, 758, 2), // "ms"
QT_MOC_LITERAL(71, 761, 23), // "sendOutputDelayToDevice"
QT_MOC_LITERAL(72, 785, 12), // "setOutputPin"
QT_MOC_LITERAL(73, 798, 3), // "pin"
QT_MOC_LITERAL(74, 802, 14), // "setChannelName"
QT_MOC_LITERAL(75, 817, 4), // "name"
QT_MOC_LITERAL(76, 822, 10), // "savePreset"
QT_MOC_LITERAL(77, 833, 10), // "loadPreset"
QT_MOC_LITERAL(78, 844, 12), // "deletePreset"
QT_MOC_LITERAL(79, 857, 13), // "setPresetName"
QT_MOC_LITERAL(80, 871, 16), // "setPresetStartup"
QT_MOC_LITERAL(81, 888, 4), // "mode"
QT_MOC_LITERAL(82, 893, 20), // "setPresetIncludePins"
QT_MOC_LITERAL(83, 914, 7), // "include"
QT_MOC_LITERAL(84, 922, 10), // "saveParams"
QT_MOC_LITERAL(85, 933, 10), // "loadParams"
QT_MOC_LITERAL(86, 944, 12), // "factoryReset"
QT_MOC_LITERAL(87, 957, 10), // "clearClips"
QT_MOC_LITERAL(88, 968, 18), // "checkCore1Conflict"
QT_MOC_LITERAL(89, 987, 11), // "scanDevices"
QT_MOC_LITERAL(90, 999, 12), // "selectDevice"
QT_MOC_LITERAL(91, 1012, 16), // "disconnectDevice"
QT_MOC_LITERAL(92, 1029, 9), // "reconnect"
QT_MOC_LITERAL(93, 1039, 14), // "channelVisible"
QT_MOC_LITERAL(94, 1054, 17), // "setChannelVisible"
QT_MOC_LITERAL(95, 1072, 7), // "visible"
QT_MOC_LITERAL(96, 1080, 9), // "connected"
QT_MOC_LITERAL(97, 1090, 14), // "selectedSerial"
QT_MOC_LITERAL(98, 1105, 16), // "availableSerials"
QT_MOC_LITERAL(99, 1122, 12), // "platformName"
QT_MOC_LITERAL(100, 1135, 11), // "numChannels"
QT_MOC_LITERAL(101, 1147, 17), // "numOutputChannels"
QT_MOC_LITERAL(102, 1165, 8), // "preampDB"
QT_MOC_LITERAL(103, 1174, 6), // "bypass"
QT_MOC_LITERAL(104, 1181, 15), // "loudnessEnabled"
QT_MOC_LITERAL(105, 1197, 14), // "loudnessRefSPL"
QT_MOC_LITERAL(106, 1212, 17), // "loudnessIntensity"
QT_MOC_LITERAL(107, 1230, 16), // "crossfeedEnabled"
QT_MOC_LITERAL(108, 1247, 15), // "crossfeedPreset"
QT_MOC_LITERAL(109, 1263, 13), // "crossfeedFreq"
QT_MOC_LITERAL(110, 1277, 13), // "crossfeedFeed"
QT_MOC_LITERAL(111, 1291, 12), // "crossfeedITD"
QT_MOC_LITERAL(112, 1304, 4), // "cpu0"
QT_MOC_LITERAL(113, 1309, 4), // "cpu1"
QT_MOC_LITERAL(114, 1314, 9), // "clipFlags"
QT_MOC_LITERAL(115, 1324, 16), // "activePresetSlot"
QT_MOC_LITERAL(116, 1341, 14), // "presetOccupied"
QT_MOC_LITERAL(117, 1356, 17), // "presetStartupMode"
QT_MOC_LITERAL(118, 1374, 17), // "presetDefaultSlot"
QT_MOC_LITERAL(119, 1392, 17), // "presetIncludePins"
QT_MOC_LITERAL(120, 1410, 9) // "core1Mode"

    },
    "DSPiBridge\0stateChanged\0\0statusChanged\0"
    "devicesChanged\0deviceArrived\0serial\0"
    "deviceDeparted\0magnitudesChanged\0"
    "pollStatus\0pollHotplug\0peakLevel\0ch\0"
    "isClipping\0channelName\0channelColor\0"
    "channelDescriptor\0filterType\0band\0"
    "filterFreq\0filterGain\0filterQ\0"
    "outputEnabled\0idx\0outputMuted\0"
    "outputGainDB\0outputDelayMS\0matrixRouting\0"
    "input\0output\0matrixGain\0matrixInvert\0"
    "outputPin\0physOut\0presetName\0slot\0"
    "isPresetOccupied\0magnitudeCurve\0eqCh\0"
    "setPreamp\0db\0sendPreampToDevice\0"
    "setBypass\0en\0setFilter\0type\0freq\0gain\0"
    "q\0setLoudness\0setLoudnessRef\0spl\0"
    "setLoudnessIntensity\0pct\0setCrossfeed\0"
    "setCrossfeedPreset\0p\0setCrossfeedFreq\0"
    "setCrossfeedFeed\0feed\0setCrossfeedITD\0"
    "setMatrixRoute\0enabled\0invert\0"
    "setOutputEnable\0setOutputGain\0"
    "sendOutputGainToDevice\0setOutputMute\0"
    "muted\0setOutputDelay\0ms\0sendOutputDelayToDevice\0"
    "setOutputPin\0pin\0setChannelName\0name\0"
    "savePreset\0loadPreset\0deletePreset\0"
    "setPresetName\0setPresetStartup\0mode\0"
    "setPresetIncludePins\0include\0saveParams\0"
    "loadParams\0factoryReset\0clearClips\0"
    "checkCore1Conflict\0scanDevices\0"
    "selectDevice\0disconnectDevice\0reconnect\0"
    "channelVisible\0setChannelVisible\0"
    "visible\0connected\0selectedSerial\0"
    "availableSerials\0platformName\0numChannels\0"
    "numOutputChannels\0preampDB\0bypass\0"
    "loudnessEnabled\0loudnessRefSPL\0"
    "loudnessIntensity\0crossfeedEnabled\0"
    "crossfeedPreset\0crossfeedFreq\0"
    "crossfeedFeed\0crossfeedITD\0cpu0\0cpu1\0"
    "clipFlags\0activePresetSlot\0presetOccupied\0"
    "presetStartupMode\0presetDefaultSlot\0"
    "presetIncludePins\0core1Mode"
};
#undef QT_MOC_LITERAL

static const uint qt_meta_data_DSPiBridge[] = {

 // content:
       8,       // revision
       0,       // classname
       0,    0, // classinfo
      66,   14, // methods
      25,  570, // properties
       0,    0, // enums/sets
       0,    0, // constructors
       0,       // flags
       6,       // signalCount

 // signals: name, argc, parameters, tag, flags
       1,    0,  344,    2, 0x06 /* Public */,
       3,    0,  345,    2, 0x06 /* Public */,
       4,    0,  346,    2, 0x06 /* Public */,
       5,    1,  347,    2, 0x06 /* Public */,
       7,    1,  350,    2, 0x06 /* Public */,
       8,    0,  353,    2, 0x06 /* Public */,

 // slots: name, argc, parameters, tag, flags
       9,    0,  354,    2, 0x08 /* Private */,
      10,    0,  355,    2, 0x08 /* Private */,

 // methods: name, argc, parameters, tag, flags
      11,    1,  356,    2, 0x02 /* Public */,
      13,    1,  359,    2, 0x02 /* Public */,
      14,    1,  362,    2, 0x02 /* Public */,
      15,    1,  365,    2, 0x02 /* Public */,
      16,    1,  368,    2, 0x02 /* Public */,
      17,    2,  371,    2, 0x02 /* Public */,
      19,    2,  376,    2, 0x02 /* Public */,
      20,    2,  381,    2, 0x02 /* Public */,
      21,    2,  386,    2, 0x02 /* Public */,
      22,    1,  391,    2, 0x02 /* Public */,
      24,    1,  394,    2, 0x02 /* Public */,
      25,    1,  397,    2, 0x02 /* Public */,
      26,    1,  400,    2, 0x02 /* Public */,
      27,    2,  403,    2, 0x02 /* Public */,
      30,    2,  408,    2, 0x02 /* Public */,
      31,    2,  413,    2, 0x02 /* Public */,
      32,    1,  418,    2, 0x02 /* Public */,
      34,    1,  421,    2, 0x02 /* Public */,
      36,    1,  424,    2, 0x02 /* Public */,
      37,    1,  427,    2, 0x02 /* Public */,
      39,    1,  430,    2, 0x02 /* Public */,
      41,    1,  433,    2, 0x02 /* Public */,
      42,    1,  436,    2, 0x02 /* Public */,
      44,    6,  439,    2, 0x02 /* Public */,
      49,    1,  452,    2, 0x02 /* Public */,
      50,    1,  455,    2, 0x02 /* Public */,
      52,    1,  458,    2, 0x02 /* Public */,
      54,    1,  461,    2, 0x02 /* Public */,
      55,    1,  464,    2, 0x02 /* Public */,
      57,    1,  467,    2, 0x02 /* Public */,
      58,    1,  470,    2, 0x02 /* Public */,
      60,    1,  473,    2, 0x02 /* Public */,
      61,    5,  476,    2, 0x02 /* Public */,
      64,    2,  487,    2, 0x02 /* Public */,
      65,    2,  492,    2, 0x02 /* Public */,
      66,    2,  497,    2, 0x02 /* Public */,
      67,    2,  502,    2, 0x02 /* Public */,
      69,    2,  507,    2, 0x02 /* Public */,
      71,    2,  512,    2, 0x02 /* Public */,
      72,    2,  517,    2, 0x02 /* Public */,
      74,    2,  522,    2, 0x02 /* Public */,
      76,    1,  527,    2, 0x02 /* Public */,
      77,    1,  530,    2, 0x02 /* Public */,
      78,    1,  533,    2, 0x02 /* Public */,
      79,    2,  536,    2, 0x02 /* Public */,
      80,    2,  541,    2, 0x02 /* Public */,
      82,    1,  546,    2, 0x02 /* Public */,
      84,    0,  549,    2, 0x02 /* Public */,
      85,    0,  550,    2, 0x02 /* Public */,
      86,    0,  551,    2, 0x02 /* Public */,
      87,    0,  552,    2, 0x02 /* Public */,
      88,    1,  553,    2, 0x02 /* Public */,
      89,    0,  556,    2, 0x02 /* Public */,
      90,    1,  557,    2, 0x02 /* Public */,
      91,    0,  560,    2, 0x02 /* Public */,
      92,    0,  561,    2, 0x02 /* Public */,
      93,    1,  562,    2, 0x02 /* Public */,
      94,    2,  565,    2, 0x02 /* Public */,

 // signals: parameters
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void, QMetaType::QString,    6,
    QMetaType::Void, QMetaType::QString,    6,
    QMetaType::Void,

 // slots: parameters
    QMetaType::Void,
    QMetaType::Void,

 // methods: parameters
    QMetaType::Float, QMetaType::Int,   12,
    QMetaType::Bool, QMetaType::Int,   12,
    QMetaType::QString, QMetaType::Int,   12,
    QMetaType::QString, QMetaType::Int,   12,
    QMetaType::QString, QMetaType::Int,   12,
    QMetaType::Int, QMetaType::Int, QMetaType::Int,   12,   18,
    QMetaType::Float, QMetaType::Int, QMetaType::Int,   12,   18,
    QMetaType::Float, QMetaType::Int, QMetaType::Int,   12,   18,
    QMetaType::Float, QMetaType::Int, QMetaType::Int,   12,   18,
    QMetaType::Bool, QMetaType::Int,   23,
    QMetaType::Bool, QMetaType::Int,   23,
    QMetaType::Float, QMetaType::Int,   23,
    QMetaType::Float, QMetaType::Int,   23,
    QMetaType::Bool, QMetaType::Int, QMetaType::Int,   28,   29,
    QMetaType::Float, QMetaType::Int, QMetaType::Int,   28,   29,
    QMetaType::Bool, QMetaType::Int, QMetaType::Int,   28,   29,
    QMetaType::Int, QMetaType::Int,   33,
    QMetaType::QString, QMetaType::Int,   35,
    QMetaType::Bool, QMetaType::Int,   35,
    QMetaType::QVariantList, QMetaType::Int,   38,
    QMetaType::Void, QMetaType::Float,   40,
    QMetaType::Void, QMetaType::Float,   40,
    QMetaType::Void, QMetaType::Bool,   43,
    QMetaType::Void, QMetaType::Int, QMetaType::Int, QMetaType::Int, QMetaType::Float, QMetaType::Float, QMetaType::Float,   12,   18,   45,   46,   47,   48,
    QMetaType::Void, QMetaType::Bool,   43,
    QMetaType::Void, QMetaType::Float,   51,
    QMetaType::Void, QMetaType::Float,   53,
    QMetaType::Void, QMetaType::Bool,   43,
    QMetaType::Void, QMetaType::Int,   56,
    QMetaType::Void, QMetaType::Float,   46,
    QMetaType::Void, QMetaType::Float,   59,
    QMetaType::Void, QMetaType::Bool,   43,
    QMetaType::Void, QMetaType::Int, QMetaType::Int, QMetaType::Bool, QMetaType::Float, QMetaType::Bool,   28,   29,   62,   47,   63,
    QMetaType::Void, QMetaType::Int, QMetaType::Bool,   29,   62,
    QMetaType::Void, QMetaType::Int, QMetaType::Float,   29,   40,
    QMetaType::Void, QMetaType::Int, QMetaType::Float,   29,   40,
    QMetaType::Void, QMetaType::Int, QMetaType::Bool,   29,   68,
    QMetaType::Void, QMetaType::Int, QMetaType::Float,   29,   70,
    QMetaType::Void, QMetaType::Int, QMetaType::Float,   29,   70,
    QMetaType::Int, QMetaType::Int, QMetaType::Int,   29,   73,
    QMetaType::Void, QMetaType::Int, QMetaType::QString,   12,   75,
    QMetaType::Int, QMetaType::Int,   35,
    QMetaType::Int, QMetaType::Int,   35,
    QMetaType::Int, QMetaType::Int,   35,
    QMetaType::Void, QMetaType::Int, QMetaType::QString,   35,   75,
    QMetaType::Void, QMetaType::Int, QMetaType::Int,   81,   35,
    QMetaType::Void, QMetaType::Bool,   83,
    QMetaType::Int,
    QMetaType::Int,
    QMetaType::Int,
    QMetaType::Void,
    QMetaType::Int, QMetaType::Int,   29,
    QMetaType::Void,
    QMetaType::Void, QMetaType::QString,    6,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Bool, QMetaType::Int,   38,
    QMetaType::Void, QMetaType::Int, QMetaType::Bool,   38,   95,

 // properties: name, type, flags
      96, QMetaType::Bool, 0x00495001,
      97, QMetaType::QString, 0x00495001,
      98, QMetaType::QStringList, 0x00495001,
      99, QMetaType::QString, 0x00495001,
     100, QMetaType::Int, 0x00495001,
     101, QMetaType::Int, 0x00495001,
     102, QMetaType::Float, 0x00495001,
     103, QMetaType::Bool, 0x00495001,
     104, QMetaType::Bool, 0x00495001,
     105, QMetaType::Float, 0x00495001,
     106, QMetaType::Float, 0x00495001,
     107, QMetaType::Bool, 0x00495001,
     108, QMetaType::Int, 0x00495001,
     109, QMetaType::Float, 0x00495001,
     110, QMetaType::Float, 0x00495001,
     111, QMetaType::Bool, 0x00495001,
     112, QMetaType::Int, 0x00495001,
     113, QMetaType::Int, 0x00495001,
     114, QMetaType::Int, 0x00495001,
     115, QMetaType::Int, 0x00495001,
     116, QMetaType::Int, 0x00495001,
     117, QMetaType::Int, 0x00495001,
     118, QMetaType::Int, 0x00495001,
     119, QMetaType::Bool, 0x00495001,
     120, QMetaType::Int, 0x00495001,

 // properties: notify_signal_id
       1,
       0,
       2,
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
       0,
       0,
       0,
       1,
       1,
       1,
       0,
       0,
       0,
       0,
       0,
       0,

       0        // eod
};

void DSPiBridge::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    if (_c == QMetaObject::InvokeMetaMethod) {
        auto *_t = static_cast<DSPiBridge *>(_o);
        (void)_t;
        switch (_id) {
        case 0: _t->stateChanged(); break;
        case 1: _t->statusChanged(); break;
        case 2: _t->devicesChanged(); break;
        case 3: _t->deviceArrived((*reinterpret_cast< const QString(*)>(_a[1]))); break;
        case 4: _t->deviceDeparted((*reinterpret_cast< const QString(*)>(_a[1]))); break;
        case 5: _t->magnitudesChanged(); break;
        case 6: _t->pollStatus(); break;
        case 7: _t->pollHotplug(); break;
        case 8: { float _r = _t->peakLevel((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< float*>(_a[0]) = std::move(_r); }  break;
        case 9: { bool _r = _t->isClipping((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 10: { QString _r = _t->channelName((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< QString*>(_a[0]) = std::move(_r); }  break;
        case 11: { QString _r = _t->channelColor((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< QString*>(_a[0]) = std::move(_r); }  break;
        case 12: { QString _r = _t->channelDescriptor((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< QString*>(_a[0]) = std::move(_r); }  break;
        case 13: { int _r = _t->filterType((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])));
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 14: { float _r = _t->filterFreq((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])));
            if (_a[0]) *reinterpret_cast< float*>(_a[0]) = std::move(_r); }  break;
        case 15: { float _r = _t->filterGain((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])));
            if (_a[0]) *reinterpret_cast< float*>(_a[0]) = std::move(_r); }  break;
        case 16: { float _r = _t->filterQ((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])));
            if (_a[0]) *reinterpret_cast< float*>(_a[0]) = std::move(_r); }  break;
        case 17: { bool _r = _t->outputEnabled((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 18: { bool _r = _t->outputMuted((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 19: { float _r = _t->outputGainDB((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< float*>(_a[0]) = std::move(_r); }  break;
        case 20: { float _r = _t->outputDelayMS((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< float*>(_a[0]) = std::move(_r); }  break;
        case 21: { bool _r = _t->matrixRouting((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 22: { float _r = _t->matrixGain((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])));
            if (_a[0]) *reinterpret_cast< float*>(_a[0]) = std::move(_r); }  break;
        case 23: { bool _r = _t->matrixInvert((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 24: { int _r = _t->outputPin((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 25: { QString _r = _t->presetName((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< QString*>(_a[0]) = std::move(_r); }  break;
        case 26: { bool _r = _t->isPresetOccupied((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 27: { QVariantList _r = _t->magnitudeCurve((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< QVariantList*>(_a[0]) = std::move(_r); }  break;
        case 28: _t->setPreamp((*reinterpret_cast< float(*)>(_a[1]))); break;
        case 29: _t->sendPreampToDevice((*reinterpret_cast< float(*)>(_a[1]))); break;
        case 30: _t->setBypass((*reinterpret_cast< bool(*)>(_a[1]))); break;
        case 31: _t->setFilter((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])),(*reinterpret_cast< int(*)>(_a[3])),(*reinterpret_cast< float(*)>(_a[4])),(*reinterpret_cast< float(*)>(_a[5])),(*reinterpret_cast< float(*)>(_a[6]))); break;
        case 32: _t->setLoudness((*reinterpret_cast< bool(*)>(_a[1]))); break;
        case 33: _t->setLoudnessRef((*reinterpret_cast< float(*)>(_a[1]))); break;
        case 34: _t->setLoudnessIntensity((*reinterpret_cast< float(*)>(_a[1]))); break;
        case 35: _t->setCrossfeed((*reinterpret_cast< bool(*)>(_a[1]))); break;
        case 36: _t->setCrossfeedPreset((*reinterpret_cast< int(*)>(_a[1]))); break;
        case 37: _t->setCrossfeedFreq((*reinterpret_cast< float(*)>(_a[1]))); break;
        case 38: _t->setCrossfeedFeed((*reinterpret_cast< float(*)>(_a[1]))); break;
        case 39: _t->setCrossfeedITD((*reinterpret_cast< bool(*)>(_a[1]))); break;
        case 40: _t->setMatrixRoute((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])),(*reinterpret_cast< bool(*)>(_a[3])),(*reinterpret_cast< float(*)>(_a[4])),(*reinterpret_cast< bool(*)>(_a[5]))); break;
        case 41: _t->setOutputEnable((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< bool(*)>(_a[2]))); break;
        case 42: _t->setOutputGain((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< float(*)>(_a[2]))); break;
        case 43: _t->sendOutputGainToDevice((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< float(*)>(_a[2]))); break;
        case 44: _t->setOutputMute((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< bool(*)>(_a[2]))); break;
        case 45: _t->setOutputDelay((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< float(*)>(_a[2]))); break;
        case 46: _t->sendOutputDelayToDevice((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< float(*)>(_a[2]))); break;
        case 47: { int _r = _t->setOutputPin((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2])));
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 48: _t->setChannelName((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< const QString(*)>(_a[2]))); break;
        case 49: { int _r = _t->savePreset((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 50: { int _r = _t->loadPreset((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 51: { int _r = _t->deletePreset((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 52: _t->setPresetName((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< const QString(*)>(_a[2]))); break;
        case 53: _t->setPresetStartup((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< int(*)>(_a[2]))); break;
        case 54: _t->setPresetIncludePins((*reinterpret_cast< bool(*)>(_a[1]))); break;
        case 55: { int _r = _t->saveParams();
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 56: { int _r = _t->loadParams();
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 57: { int _r = _t->factoryReset();
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 58: _t->clearClips(); break;
        case 59: { int _r = _t->checkCore1Conflict((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< int*>(_a[0]) = std::move(_r); }  break;
        case 60: _t->scanDevices(); break;
        case 61: _t->selectDevice((*reinterpret_cast< const QString(*)>(_a[1]))); break;
        case 62: _t->disconnectDevice(); break;
        case 63: _t->reconnect(); break;
        case 64: { bool _r = _t->channelVisible((*reinterpret_cast< int(*)>(_a[1])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 65: _t->setChannelVisible((*reinterpret_cast< int(*)>(_a[1])),(*reinterpret_cast< bool(*)>(_a[2]))); break;
        default: ;
        }
    } else if (_c == QMetaObject::IndexOfMethod) {
        int *result = reinterpret_cast<int *>(_a[0]);
        {
            using _t = void (DSPiBridge::*)();
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&DSPiBridge::stateChanged)) {
                *result = 0;
                return;
            }
        }
        {
            using _t = void (DSPiBridge::*)();
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&DSPiBridge::statusChanged)) {
                *result = 1;
                return;
            }
        }
        {
            using _t = void (DSPiBridge::*)();
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&DSPiBridge::devicesChanged)) {
                *result = 2;
                return;
            }
        }
        {
            using _t = void (DSPiBridge::*)(const QString & );
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&DSPiBridge::deviceArrived)) {
                *result = 3;
                return;
            }
        }
        {
            using _t = void (DSPiBridge::*)(const QString & );
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&DSPiBridge::deviceDeparted)) {
                *result = 4;
                return;
            }
        }
        {
            using _t = void (DSPiBridge::*)();
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&DSPiBridge::magnitudesChanged)) {
                *result = 5;
                return;
            }
        }
    }
#ifndef QT_NO_PROPERTIES
    else if (_c == QMetaObject::ReadProperty) {
        auto *_t = static_cast<DSPiBridge *>(_o);
        (void)_t;
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast< bool*>(_v) = _t->connected(); break;
        case 1: *reinterpret_cast< QString*>(_v) = _t->selectedSerial(); break;
        case 2: *reinterpret_cast< QStringList*>(_v) = _t->availableSerials(); break;
        case 3: *reinterpret_cast< QString*>(_v) = _t->platformName(); break;
        case 4: *reinterpret_cast< int*>(_v) = _t->numChannels(); break;
        case 5: *reinterpret_cast< int*>(_v) = _t->numOutputChannels(); break;
        case 6: *reinterpret_cast< float*>(_v) = _t->preampDB(); break;
        case 7: *reinterpret_cast< bool*>(_v) = _t->bypass(); break;
        case 8: *reinterpret_cast< bool*>(_v) = _t->loudnessEnabled(); break;
        case 9: *reinterpret_cast< float*>(_v) = _t->loudnessRefSPL(); break;
        case 10: *reinterpret_cast< float*>(_v) = _t->loudnessIntensity(); break;
        case 11: *reinterpret_cast< bool*>(_v) = _t->crossfeedEnabled(); break;
        case 12: *reinterpret_cast< int*>(_v) = _t->crossfeedPreset(); break;
        case 13: *reinterpret_cast< float*>(_v) = _t->crossfeedFreq(); break;
        case 14: *reinterpret_cast< float*>(_v) = _t->crossfeedFeed(); break;
        case 15: *reinterpret_cast< bool*>(_v) = _t->crossfeedITD(); break;
        case 16: *reinterpret_cast< int*>(_v) = _t->cpu0(); break;
        case 17: *reinterpret_cast< int*>(_v) = _t->cpu1(); break;
        case 18: *reinterpret_cast< int*>(_v) = _t->clipFlags(); break;
        case 19: *reinterpret_cast< int*>(_v) = _t->activePresetSlot(); break;
        case 20: *reinterpret_cast< int*>(_v) = _t->presetOccupied(); break;
        case 21: *reinterpret_cast< int*>(_v) = _t->presetStartupMode(); break;
        case 22: *reinterpret_cast< int*>(_v) = _t->presetDefaultSlot(); break;
        case 23: *reinterpret_cast< bool*>(_v) = _t->presetIncludePins(); break;
        case 24: *reinterpret_cast< int*>(_v) = _t->core1Mode(); break;
        default: break;
        }
    } else if (_c == QMetaObject::WriteProperty) {
    } else if (_c == QMetaObject::ResetProperty) {
    }
#endif // QT_NO_PROPERTIES
}

QT_INIT_METAOBJECT const QMetaObject DSPiBridge::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_meta_stringdata_DSPiBridge.data,
    qt_meta_data_DSPiBridge,
    qt_static_metacall,
    nullptr,
    nullptr
} };


const QMetaObject *DSPiBridge::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *DSPiBridge::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_meta_stringdata_DSPiBridge.stringdata0))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int DSPiBridge::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 66)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 66;
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 66)
            *reinterpret_cast<int*>(_a[0]) = -1;
        _id -= 66;
    }
#ifndef QT_NO_PROPERTIES
    else if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 25;
    } else if (_c == QMetaObject::QueryPropertyDesignable) {
        _id -= 25;
    } else if (_c == QMetaObject::QueryPropertyScriptable) {
        _id -= 25;
    } else if (_c == QMetaObject::QueryPropertyStored) {
        _id -= 25;
    } else if (_c == QMetaObject::QueryPropertyEditable) {
        _id -= 25;
    } else if (_c == QMetaObject::QueryPropertyUser) {
        _id -= 25;
    }
#endif // QT_NO_PROPERTIES
    return _id;
}

// SIGNAL 0
void DSPiBridge::stateChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 0, nullptr);
}

// SIGNAL 1
void DSPiBridge::statusChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 1, nullptr);
}

// SIGNAL 2
void DSPiBridge::devicesChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 2, nullptr);
}

// SIGNAL 3
void DSPiBridge::deviceArrived(const QString & _t1)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))) };
    QMetaObject::activate(this, &staticMetaObject, 3, _a);
}

// SIGNAL 4
void DSPiBridge::deviceDeparted(const QString & _t1)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))) };
    QMetaObject::activate(this, &staticMetaObject, 4, _a);
}

// SIGNAL 5
void DSPiBridge::magnitudesChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 5, nullptr);
}
QT_WARNING_POP
QT_END_MOC_NAMESPACE

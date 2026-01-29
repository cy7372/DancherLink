message("Check QMAKE_MSC_VER: $$QMAKE_MSC_VER")
isEmpty(QMAKE_MSC_VER): error("QMAKE_MSC_VER is empty")
else: message("QMAKE_MSC_VER is set")

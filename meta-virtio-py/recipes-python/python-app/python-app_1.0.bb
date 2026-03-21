SUMMARY = "Python application started at boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://app.py \
           file://python-app"

S = "${UNPACKDIR}"

inherit update-rc.d

INITSCRIPT_NAME = "python-app"
INITSCRIPT_PARAMS = "defaults 90"

RDEPENDS:${PN} = "python3"

do_install() {
    install -d ${D}/opt/app
    install -m 0755 ${UNPACKDIR}/app.py ${D}/opt/app/app.py

    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${UNPACKDIR}/python-app ${D}${sysconfdir}/init.d/python-app
}

FILES:${PN} += "/opt/app/app.py"

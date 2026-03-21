#!/bin/bash
# run.sh - Build the Yocto image and run it in QEMU.
#
# Usage:
#   ./run.sh build        - build the image
#   ./run.sh run          - run the image in QEMU (serial console on stdio)
#   ./run.sh all          - build then run
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISTRO="oe-nodistro-whinlatter"
BUILD_DIR="$SCRIPT_DIR/build"
MACHINE="qemux86-64"
IMAGE="virtio-image"
SERIAL_PTY="/tmp/qemu-serial.pty"
VIRTIO_SERIAL_SOCK="/tmp/virtio-serial.sock"
CARGO_BIN="${SCRIPT_DIR}/vhost-stubs/target/release"
VHOST_I2C_SOCK="/tmp/vhost-i2c.sock"
VHOST_GPIO_SOCK="/tmp/vhost-gpio.sock"
VHOST_SPI_SOCK="/tmp/vhost-spi.sock"

# ── helpers ──────────────────────────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo ">>> $*"; }
require() { command -v "$1" &>/dev/null || die "'$1' not found. Install it first."; }

# ── build ─────────────────────────────────────────────────────────────────────

cmd_build() {
    set +u
    TEMPLATECONF=$SCRIPT_DIR/meta-yocto/meta-poky/conf/templates/default
    source $SCRIPT_DIR/openembedded-core/oe-init-build-env
    export BB_NUMBER_THREADS="8"
    export PARALLEL_MAKE="-j 8"
    bitbake "$IMAGE"
}

# ── run ───────────────────────────────────────────────────────────────────────

cmd_run() {
    require qemu-system-x86_64
    DEPLOY="$BUILD_DIR/tmp/deploy/images/$MACHINE"
    KERNEL=$(find "$DEPLOY" -maxdepth 1 -name 'bzImage-*' 2>/dev/null | head -1)
    ROOTFS=$(find "$DEPLOY" -maxdepth 1 -name "${IMAGE}-${MACHINE}.rootfs.ext4" 2>/dev/null | head -1)
    [ -f "$KERNEL" ] || die "Kernel image not found in $DEPLOY. Run './run.sh build' first."
    [ -f "$ROOTFS" ] || die "Root filesystem not found in $DEPLOY. Run './run.sh build' first."
    info "Booting $IMAGE image in QEMU..."
    info "Kernel: $KERNEL"
    info "Root filesystem: $ROOTFS"


    # Start vhost-user daemons (dummy backends — no real hardware needed)
    rm -f "${VHOST_I2C_SOCK}0" "${VHOST_GPIO_SOCK}0" "${VHOST_SPI_SOCK}0" "$SERIAL_PTY" "$VIRTIO_SERIAL_SOCK"
    VHOST_I2C_PID="" VHOST_GPIO_PID="" VHOST_SPI_PID=""

    if [ -x "$CARGO_BIN/vhost-device-i2c" ]; then
        RUST_LOG=info "$CARGO_BIN/vhost-device-i2c" \
            --socket-path "$VHOST_I2C_SOCK" \
            --device-list "0:80" >/tmp/vhost-i2c.log 2>&1 &
        VHOST_I2C_PID=$!
        info "vhost-device-i2c (dummy) started (pid $VHOST_I2C_PID)"
    fi

    if [ -x "$CARGO_BIN/vhost-device-gpio" ]; then
        "$CARGO_BIN/vhost-device-gpio" \
            --socket-path "$VHOST_GPIO_SOCK" \
            --device-list "0" >/tmp/vhost-gpio.log 2>&1 &
        VHOST_GPIO_PID=$!
        info "vhost-device-gpio started (pid $VHOST_GPIO_PID)"
    fi

    if [ -x "$CARGO_BIN/vhost-device-spi" ]; then
        "$CARGO_BIN/vhost-device-spi" \
            --socket-path "$VHOST_SPI_SOCK" \
            --device-list "0" >/tmp/vhost-spi.log 2>&1 &
        VHOST_SPI_PID=$!
        info "vhost-device-spi started (pid $VHOST_SPI_PID)"
    fi

    # Wait for sockets (daemon appends '0' to socket path)
    for sock in "${VHOST_I2C_SOCK}0" "${VHOST_GPIO_SOCK}0" "${VHOST_SPI_SOCK}0"; do
        for i in $(seq 1 10); do
            [ -S "$sock" ] && break
            sleep 0.5
        done
        [ -S "$sock" ] && info "Socket ready: $sock" || info "Socket not ready: $sock"
    done

    echo "Starting QEMU... (serial console on stdio, Ctrl-A X to quit)"

    # Build vhost-user device args (use sock0 — the actual socket file)
    VHOST_ARGS=()
    if [ -S "${VHOST_I2C_SOCK}0" ]; then
        VHOST_ARGS+=(-chardev "socket,path=${VHOST_I2C_SOCK}0,id=vhost-i2c")
        VHOST_ARGS+=(-device "vhost-user-i2c-pci,chardev=vhost-i2c,id=i2c0")
    fi
    if [ -S "${VHOST_GPIO_SOCK}0" ]; then
        VHOST_ARGS+=(-chardev "socket,path=${VHOST_GPIO_SOCK}0,id=vhost-gpio")
        VHOST_ARGS+=(-device "vhost-user-gpio-pci,chardev=vhost-gpio,id=gpio0")
    fi
    if [ -S "${VHOST_SPI_SOCK}0" ]; then
        VHOST_ARGS+=(-chardev "socket,path=${VHOST_SPI_SOCK}0,id=vhost-spi")
        VHOST_ARGS+=(-device "vhost-user-spi-pci,chardev=vhost-spi,id=spi0")
    fi

    qemu-system-x86_64 \
        -nographic \
        -cpu max \
        -kernel "$KERNEL" \
        -drive file="$ROOTFS",format=raw,if=virtio \
        -append "root=/dev/vda rw console=ttyS0,115200 console=ttyS1,115200 quiet" \
        -m 512M \
        -serial mon:stdio \
        -serial "unix:$SERIAL_PTY,server,nowait" \
        -device virtio-serial-pci \
        -chardev "socket,path=$VIRTIO_SERIAL_SOCK,server,nowait,id=vser0" \
        -device "virtserialport,chardev=vser0,name=virtio-serial0" \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -object memory-backend-memfd,id=mem,size=512M,share=on \
        -numa node,memdev=mem \
        "${VHOST_ARGS[@]}"

    # Cleanup daemons on exit
    kill "${VHOST_I2C_PID:-}" "${VHOST_GPIO_PID:-}" "${VHOST_SPI_PID:-}" 2>/dev/null || true
    rm -f "${VHOST_I2C_SOCK}0" "${VHOST_GPIO_SOCK}0" "${VHOST_SPI_SOCK}0" "$SERIAL_PTY" "$VIRTIO_SERIAL_SOCK"
}

cmd_virtio() {
    require socat
    [ -S "$VIRTIO_SERIAL_SOCK" ] || die "Socket $VIRTIO_SERIAL_SOCK not found. Is QEMU running?"
    echo "Connecting to VirtIO Serial... (Ctrl-C to exit)"
    # 'crlf' converts local newline (\n) to the carriage return (\r) expected by serial devices
    socat STDIO,crlf UNIX-CONNECT:"$VIRTIO_SERIAL_SOCK"
}

cmd_serial() {
    require minicom
    require socat
    [ -S "$SERIAL_PTY" ] || die "Socket $SERIAL_PTY not found. Is QEMU running?"

    local BRIDGE_PTY="/tmp/qemu-ttyS1-bridge"
    rm -f "$BRIDGE_PTY"

    echo "Starting bridge (socat) to $SERIAL_PTY..."
    socat PTY,link="$BRIDGE_PTY",raw,echo=0,crnl UNIX-CONNECT:"$SERIAL_PTY" &
    local SOCAT_PID=$!
    sleep 1 # Wait for PTY creation

    echo "Starting minicom on $BRIDGE_PTY..."
    minicom -D "$BRIDGE_PTY" || true

    kill "$SOCAT_PID" 2>/dev/null || true
    rm -f "$BRIDGE_PTY"
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "${1:-}" in
    build)  cmd_build ;;
    run)    cmd_run ;;
    virtio) cmd_virtio ;;
    serial) cmd_serial ;;
    all)    cmd_build && cmd_run ;;
    *)
        echo "Usage: $0 {build|run|virtio|serial|all}"
        exit 1
        ;;
esac

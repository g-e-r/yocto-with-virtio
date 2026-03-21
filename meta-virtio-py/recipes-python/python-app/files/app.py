#!/usr/bin/env python3
"""
Probe VirtIO I2C, SPI, GPIO, and serial devices.
Prints what's found and attempts basic operations on each.
"""

import os
import sys
import glob
import struct
import fcntl

# ── I2C ───────────────────────────────────────────────────────────────────────

I2C_RETRIES     = 0x0701
I2C_RDWR        = 0x0707
I2C_SMBUS       = 0x0720
I2C_SLAVE       = 0x0703

def probe_i2c():
    buses = sorted(glob.glob("/dev/i2c-*"))
    if not buses:
        print("[I2C] No I2C buses found")
        return
    for bus in buses:
        print(f"[I2C] Found bus: {bus}")
        try:
            with open(bus, "rb", buffering=0) as f:
                # Scan addresses 0x03–0x77
                found = []
                for addr in range(0x03, 0x78):
                    try:
                        fcntl.ioctl(f, I2C_SLAVE, addr)
                        # Try a 1-byte read
                        f.read(1)
                        found.append(hex(addr))
                    except OSError:
                        pass
                print(f"[I2C]   Devices on {bus}: {found if found else 'none'}")
        except OSError as e:
            print(f"[I2C]   Could not open {bus}: {e}")

# ── SPI ───────────────────────────────────────────────────────────────────────

SPI_IOC_WR_MODE          = 0x40016b01
SPI_IOC_RD_BITS_PER_WORD = 0x80016b03

def probe_spi():
    devices = sorted(glob.glob("/dev/spidev*"))
    if not devices:
        print("[SPI] No SPI devices found")
        return
    for dev in devices:
        print(f"[SPI] Found device: {dev}")
        try:
            with open(dev, "rb", buffering=0) as f:
                mode = struct.pack("B", 0)
                fcntl.ioctl(f, SPI_IOC_WR_MODE, mode)
                bits = bytearray(1)
                fcntl.ioctl(f, SPI_IOC_RD_BITS_PER_WORD, bits)
                print(f"[SPI]   {dev}: mode=0, bits_per_word={bits[0]}")
        except OSError as e:
            print(f"[SPI]   Could not open {dev}: {e}")

# ── GPIO ──────────────────────────────────────────────────────────────────────

def probe_gpio():
    chips = sorted(glob.glob("/dev/gpiochip*"))
    if not chips:
        print("[GPIO] No GPIO chips found")
        return
    for chip in chips:
        print(f"[GPIO] Found chip: {chip}")
        # Read chip info via ioctl (GPIO_GET_CHIPINFO_IOCTL = 0x8044b401)
        try:
            with open(chip, "rb", buffering=0) as f:
                # struct gpiochip_info: name[32], label[32], lines(u32)
                buf = bytearray(68)
                fcntl.ioctl(f, 0x8044B401, buf)
                name  = buf[0:32].rstrip(b'\x00').decode()
                label = buf[32:64].rstrip(b'\x00').decode()
                lines = struct.unpack_from("I", buf, 64)[0]
                print(f"[GPIO]   name={name}, label={label}, lines={lines}")
        except OSError as e:
            print(f"[GPIO]   Could not read chip info: {e}")

# ── Serial ────────────────────────────────────────────────────────────────────

def probe_serial():
    # ttyS* = UART, hvc* = virtio console, vport* = virtio serial ports
    ports = (sorted(glob.glob("/dev/ttyS*")) +
             sorted(glob.glob("/dev/hvc*")) +
             sorted(glob.glob("/dev/vport*")))
    if not ports:
        print("[Serial] No serial ports found")
        return
    for port in ports:
        exists = os.path.exists(port)
        print(f"[Serial] {'Found' if exists else 'Missing'}: {port}")

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":

    if len(sys.argv) > 1:
        sys.stdout = open(sys.argv[1], "w")
    
    print("=== VirtIO Device Probe ===")
    probe_i2c()
    probe_spi()
    probe_gpio()
    probe_serial()
    print("=== Done ===")

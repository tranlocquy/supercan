STM32H725ZGT6 custom target
===========================

This firmware target is a baseline for a custom board using the 1 MiB,
LQFP144 STM32H725ZGT6. It is not a pin-compatible replacement for the
NUCLEO-H7A3ZI-Q and it does not describe a complete PCB. The target exposes
one or two independent SuperCAN channels. Channel 0 uses FDCAN1 and optional
channel 1 uses FDCAN2.

**Each channel requires its own external CAN-FD transceiver. Never connect
PB5, PB6, PB8, or PB9 directly to CANH or CANL.**

Build target
============

Use ``BOARD=stm32h725zgt6``. From the SuperCAN repository root::

  git submodule update --init Boards
  git -C Boards submodule update --init \
    lib/CMSIS_5 lib/FreeRTOS-Kernel \
    hw/mcu/st/cmsis_device_h7 \
    hw/mcu/st/stm32h7xx_hal_driver
  cd Boards/examples/device/supercan
  make BOARD=stm32h725zgt6 STM32H725_FDCAN_COUNT=2

``STM32H725_FDCAN_COUNT`` accepts only ``1`` or ``2`` and defaults to ``2``
when omitted. To build a single-channel image instead::

  make BOARD=stm32h725zgt6 STM32H725_FDCAN_COUNT=1

The two-channel build creates ``_build/stm32h725zgt6/supercan.elf``,
``supercan.hex``, and ``supercan.bin``. The single-channel output is kept in
``_build/stm32h725zgt6-fdcan1`` so changing the flag cannot reuse objects from
the other configuration. The image is linked for the start of internal flash
at ``0x08000000``. The target can be flashed over SWD with the ``flash-jlink``
or ``flash-stlink`` make targets. ST's factory USB DFU bootloader is another
option when the PCB boot configuration supports it; SuperDFU is not provided
for this target.

The channel count also controls the USB configuration: the single-channel
image exposes one SuperCAN vendor interface, while the default image exposes
two.

Default signal map
==================

The target places both FDCAN pin pairs on GPIOB:

+----------------------+----------+------------+-----------------------------------------------+
| Function             | Signal   | LQFP144 pin| Configuration                                 |
+======================+==========+============+===============================================+
| FDCAN1 RX            | PB8      | 136        | AF9; connect from CAN-FD transceiver RXD      |
+----------------------+----------+------------+-----------------------------------------------+
| FDCAN1 TX            | PB9      | 137        | AF9; connect to CAN-FD transceiver TXD        |
+----------------------+----------+------------+-----------------------------------------------+
| FDCAN2 RX            | PB5      | 132        | AF9; connect from CAN-FD transceiver RXD      |
+----------------------+----------+------------+-----------------------------------------------+
| FDCAN2 TX            | PB6      | 133        | AF9; connect to CAN-FD transceiver TXD        |
+----------------------+----------+------------+-----------------------------------------------+
| USB device D-        | PA11     | 100        | USB1 OTG HS controller, internal FS PHY       |
+----------------------+----------+------------+-----------------------------------------------+
| USB device D+        | PA12     | 101        | USB1 OTG HS controller, internal FS PHY       |
+----------------------+----------+------------+-----------------------------------------------+
| USB OTG ID           | PA10     | 99         | AF10, open-drain with pull-up                 |
+----------------------+----------+------------+-----------------------------------------------+
| USB supply input     | VDD50USB | 90         | Wire for external or internal-regulator mode  |
+----------------------+----------+------------+-----------------------------------------------+
| USB PHY supply       | VDD33USB | 91         | External 3.3 V or internal-regulator output   |
+----------------------+----------+------------+-----------------------------------------------+
| Debug UART TX        | PD8      | 76         | USART3 TX, AF7                                |
+----------------------+----------+------------+-----------------------------------------------+
| Debug UART RX        | PD9      | 77         | USART3 RX, AF7                                |
+----------------------+----------+------------+-----------------------------------------------+
| Debug/status LED     | PE1      | 139        | Push-pull output, active high                 |
+----------------------+----------+------------+-----------------------------------------------+
| CAN0 green LED       | PB0      | 49         | Push-pull output, active high                 |
+----------------------+----------+------------+-----------------------------------------------+
| CAN0 red LED         | PB14     | 74         | Push-pull output, active high                 |
+----------------------+----------+------------+-----------------------------------------------+
| User button          | PC13     | 9          | Input, no internal pull, active high          |
+----------------------+----------+------------+-----------------------------------------------+

PB5/PB6 are configured for FDCAN2 only when ``STM32H725_FDCAN_COUNT=2``.
The single-channel build leaves them in their reset state for other board
functions. If a second CAN transceiver is populated in that configuration,
hold it in standby or provide a pull that keeps its TXD input recessive.

The LED and button assignments are firmware defaults, not fixed features of
the MCU. Change them in the target BSP if the custom PCB uses other pins. The
default mapping provides status LEDs for channel 0 only; channel 1 operates
without dedicated status LEDs. The firmware does not define transceiver
enable or standby GPIOs, so the PCB must strap those inputs for normal
operation or extend the target with control pins.

Clock and memory configuration
==============================

The default board support package uses only internal oscillators:

* HSI64 and PLL1 produce a 120 MHz system and AXI clock.
* HSI48 supplies the 48 MHz USB kernel clock.
* PLL2 Q supplies a 60 MHz FDCAN kernel clock. APB1 also runs at 60 MHz, which
  stays inside the VOS2 limit and meets the FDCAN peripheral-clock rule.
* TIM2 is a free-running 1 MHz SuperCAN timestamp counter.
* The linker describes 1 MiB internal flash and the STM32H725's 560 KiB of
  normal SRAM. Initialized data, RAM-resident code, BSS, heap, and stack stay
  inside the first 128 KiB of AXI SRAM, which exists for every supported
  ITCM/AXI option-byte split.

The additional 192 KiB ``AXIRAM_EXT`` linker region is available in full only
with the default 64 KiB ITCM / 320 KiB AXI SRAM option-byte split. The firmware
does not place anything there automatically. Verify the option bytes before
assigning custom sections to that region.

FDCAN1, FDCAN2, and FDCAN3 share one fixed 10 KiB CAN message RAM. Both build
modes use 32 transmit FIFO and 32 transmit-event elements per enabled
controller. The single-channel mode restores the hardware maximum of 64
receive elements and uses this layout::

  0x0000 - 0x1bff  FDCAN1: 7,168 bytes
  0x1c00 - 0x27ff  Unused:  3,072 bytes

The two-channel mode uses 32 receive elements per controller and partitions
the message RAM as follows::

  0x0000 - 0x12ff  FDCAN1: 4,864 bytes
  0x1300 - 0x25ff  FDCAN2: 4,864 bytes
  0x2600 - 0x27ff  Unused:    512 bytes

The regions are offsets from ``SRAMCAN_BASE`` and do not overlap. The hardware
message RAM cannot be enlarged or relocated into normal SRAM. SuperCAN also
maintains per-channel software queues in normal SRAM and drains the smaller
hardware FIFOs from the interrupt handlers. FDCAN3 is not exposed because the
current SuperCAN USB implementation supports at most two CAN interfaces.
The target disables FDCAN edge filtering as required by STM32H725 erratum
ES0491 section 2.22.1.

In the two-channel image, both CAN channels share the USB full-speed link.
Dual-channel operation does not guarantee lossless capture when both CAN-FD
buses are simultaneously near their maximum configured load; validate
aggregate throughput for the application and monitor the SuperCAN loss
counters.

Power and USB hardware requirements
===================================

The default build selects ``PWR_LDO_SUPPLY``. The PCB must therefore supply
VDDLDO and decouple VCAP exactly as required by the STM32H725 hardware design
guidance. The LQFP144 device also supports SMPS configurations. If the PCB uses
one, select the matching STM32 HAL supply mode at build time, for example::

  make BOARD=stm32h725zgt6 \
    STM32H725_SUPPLY=PWR_DIRECT_SMPS_SUPPLY

The selected constant must match the physical power topology; firmware cannot
make an LDO schematic behave as an SMPS schematic or vice versa.

PA11 and PA12 use the on-chip full-speed PHY in the USB1 OTG HS controller, so
an external ULPI PHY is not needed. The shared BSP also configures PA10/ID, but
a fixed USB device can leave that signal unconnected. This target does not
configure PA9/OTG_HS_VBUS (LQFP144 pin 98); it disables pin-based VBUS sensing
and forces a valid device session. This is suitable only when the product's
power and attach behavior allow it. In particular, a self-powered USB device
must implement the required VBUS presence detection and update the BSP.

By default, the firmware leaves the internal USB regulator disabled. The PCB
must externally supply VDD33USB at 3.3 V, connect VDD50USB as specified for the
regulator-bypass case, and fit ST's required capacitors. If the PCB instead
feeds the internal regulator through VDD50USB and uses VDD33USB only as its
decoupled output, enable that regulator explicitly::

  make BOARD=stm32h725zgt6 \
    STM32H725_USB_INTERNAL_REGULATOR=1

Do not enable the internal regulator when VDD33USB is driven by an external
3.3 V supply; that would create supply contention. Both arrangements must
follow the voltage ranges, connections, and decoupling in the datasheet and
AN5419.

References
==========

* `STM32H725/735 datasheet <https://www.st.com/resource/en/datasheet/stm32h725ae.pdf>`_
* `AN5419: STM32H72x/73x hardware development <https://www.st.com/resource/en/application_note/an5419-getting-started-with-stm32h723733-stm32h725735-and-stm32h730-value-line-hardware-development-stmicroelectronics.pdf>`_
* `AN5348: FDCAN peripheral on STM32 devices <https://www.st.com/resource/en/application_note/dm00625700-fdcan-peripheral-on-stm32-devices-stmicroelectronics.pdf>`_
* `AN4879: USB hardware and PCB guidelines <https://www.st.com/resource/en/application_note/an4879-usb-hardware-and-pcb-guidelines-using-stm32-mcus-stmicroelectronics.pdf>`_
* `ES0491: STM32H72xx/73xx device errata <https://www.st.com/resource/en/errata_sheet/es0491-stm32h72xx73xx-device-errata-stmicroelectronics.pdf>`_
* `RM0468: STM32H723/733, STM32H725/735, and STM32H730 reference manual <https://www.st.com/resource/en/reference_manual/dm00603761.pdf>`_
* `STM32H725ZG product page <https://www.st.com/en/microcontrollers-microprocessors/stm32h725zg.html>`_

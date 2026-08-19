STM32H735ZGT6 custom target
===========================

This target supports custom hardware using the 1 MiB, LQFP144
STM32H735ZGT6. ``STM32H735ZTG6`` is not a valid ST ordering code: for this
device, ``G`` identifies the 1 MiB flash size and ``T`` identifies the LQFP
package.

The STM32H735ZGT6 is the crypto-enabled counterpart of the STM32H725ZGT6.
The two devices have the same package footprint, memory map, SuperCAN pin
assignments, USB peripheral, clock tree, and three FDCAN instances. Use this
dedicated H735 target rather than shipping an H725-labelled image, because
the H735 has its own CMSIS device header and interrupt vector table.

Build target
============

Use ``BOARD=stm32h735zgt6``. From the SuperCAN repository root::

  git submodule update --init Boards
  git -C Boards submodule update --init \
    lib/CMSIS_5 lib/FreeRTOS-Kernel \
    hw/mcu/st/cmsis_device_h7 \
    hw/mcu/st/stm32h7xx_hal_driver
  cd Boards/examples/device/supercan
  make BOARD=stm32h735zgt6 STM32H735_FDCAN_COUNT=2

``STM32H735_FDCAN_COUNT`` accepts ``1``, ``2``, or ``3`` and defaults to
``2``. Single- and three-channel builds are selected with::

  make BOARD=stm32h735zgt6 STM32H735_FDCAN_COUNT=1
  make BOARD=stm32h735zgt6 STM32H735_FDCAN_COUNT=3

The default clock source is HSI64. Select a 25 MHz crystal between PH0 and
PH1 with::

  make BOARD=stm32h735zgt6 STM32H735_USE_HSE=1

``STM32H735_USE_HSE`` accepts exactly ``0`` or ``1`` and defaults to ``0``.
It can be combined with any supported channel count.

Build outputs are isolated by configuration:

* two-channel HSI: ``_build/stm32h735zgt6``
* one-channel HSI: ``_build/stm32h735zgt6-fdcan1``
* three-channel HSI: ``_build/stm32h735zgt6-fdcan3``
* HSE builds: append ``-hse25`` to the corresponding directory

Each directory contains ``supercan.elf``, ``supercan.hex``, and
``supercan.bin``. The image is linked at ``0x08000000``. The release script
intentionally packages the default two-channel HSI image.

Signal map
==========

Each enabled channel requires its own external CAN-FD transceiver. Never
connect an MCU FDCAN RX or TX pin directly to CANH or CANL.

.. list-table:: Default STM32H735ZGT6 LQFP144 assignments
   :header-rows: 1
   :widths: 24 16 14 46

   * - Function
     - Signal
     - Pin
     - Configuration
   * - FDCAN1 RX
     - PB8
     - 136
     - AF9; connect from transceiver RXD
   * - FDCAN1 TX
     - PB9
     - 137
     - AF9; connect to transceiver TXD
   * - FDCAN2 RX
     - PB5
     - 132
     - AF9; connect from transceiver RXD
   * - FDCAN2 TX
     - PB6
     - 133
     - AF9; connect to transceiver TXD
   * - FDCAN3 RX
     - PG10
     - 123
     - AF2; connect from transceiver RXD
   * - FDCAN3 TX
     - PG9
     - 122
     - AF2; connect to transceiver TXD
   * - USB D-
     - PA11
     - 100
     - USB1 OTG HS controller, embedded FS PHY
   * - USB D+
     - PA12
     - 101
     - USB1 OTG HS controller, embedded FS PHY
   * - USB ID
     - PA10
     - 99
     - AF10; optional on a fixed USB device
   * - Unused UART pins
     - PD8 / PD9
     - 76 / 77
     - Not configured; USART3 is disabled
   * - Blue debug LED
     - PE2
     - 1
     - GPIO open-drain output; active low
   * - Green CAN0 LED
     - PE3
     - 2
     - GPIO open-drain output; active low
   * - Red CAN0 LED
     - PE4
     - 3
     - GPIO open-drain output; active low
   * - Unused legacy LED pins
     - PB0 / PB14 / PE1
     - 49 / 74 / 139
     - Not configured
   * - Unused button pin
     - PC13
     - 9
     - Not configured or read
   * - 25 MHz HSE
     - PH0 / PH1
     - 25 / 26
     - Crystal mode, not bypass mode
   * - SWD data / clock
     - PA13 / PA14
     - 102 / 107
     - SWDIO / SWCLK

PB5/PB6 are configured only when the channel count is ``2`` or ``3``.
PG10/PG9 are configured only when the count is ``3``. If an unused
transceiver is populated, hold it in standby or ensure its TXD input remains
recessive. The firmware does not currently define transceiver-enable GPIOs.

The H735 target drives PE2/PE3/PE4 as active-low, open-drain LEDs. Wire each
LED from the positive supply through its current-limiting resistor to the MCU
pin: driving the pin low turns the LED on, while releasing it high turns the
LED off. The blue LED provides the debug/startup indication; the green and red
LEDs report CAN0 status. FDCAN2 and FDCAN3 do not have dedicated status LEDs.
PE2/PE3/PE4 can alternatively carry TRACECLK/TRACED0/TRACED1, so parallel
trace is unavailable while the LEDs are enabled; normal SWD on PA13/PA14 is
unaffected.

The target still disables the legacy debug UART and user button. It does not
enable USART3 or configure PD8, PD9, PB0, PB14, PE1, or PC13, leaving those
GPIOs in their reset state for the application board.

Clock and memory configuration
==============================

The default HSI clock configuration is:

* HSI64 / 4 x 15 / 2 = 120 MHz SYSCLK
* APB1 = 60 MHz
* PLL2 Q = 80 MHz FDCAN kernel clock
* CCU divider 2 = 40 MHz FDCAN time-quanta clock
* HSI48 = 48 MHz USB kernel clock
* TIM2 = 1 MHz SuperCAN timestamp counter

The 40 MHz time-quanta clock is strictly below the 60 MHz APB1 peripheral
clock, as required by ST's FDCAN clock guidance.

The optional HSE configuration uses a 25 MHz crystal:

* 25 MHz / 5 x 48 / 2 = 120 MHz SYSCLK
* 25 MHz / 5 x 48 / 3 = 80 MHz FDCAN kernel clock
* CCU divider 2 = 40 MHz FDCAN time-quanta clock

There is no automatic fallback to HSI. If an HSE image is used without a
working crystal, startup does not reach USB or SuperCAN.

The linker describes 1 MiB of flash and the STM32H735's 560 KiB of normal
SRAM plus 4 KiB of backup SRAM. Automatic data, BSS, heap, and stack remain
inside the guaranteed first 128 KiB of AXI SRAM. The additional 192 KiB
``AXIRAM_EXT`` region assumes the default 64 KiB ITCM / 320 KiB AXI split and
is not used automatically.

FDCAN message RAM
=================

FDCAN1, FDCAN2, and FDCAN3 share one fixed 10 KiB message RAM. It cannot be
expanded or moved into ordinary SRAM. The layouts are:

* one channel: FDCAN1 uses ``0x0000-0x1bff``
* two channels: FDCAN1 uses ``0x0000-0x12ff`` and FDCAN2 uses
  ``0x1300-0x25ff``
* three channels: FDCAN1 uses ``0x0000-0x0cbf``, FDCAN2 uses
  ``0x0cc0-0x197f``, and FDCAN3 uses ``0x1980-0x263f``

The three-channel build retains 32 receive elements per controller and uses
12 transmit plus 12 transmit-event elements per controller. All channels
share one 12 Mbit/s USB full-speed link, so simultaneous maximum-load CAN-FD
traffic requires application-specific stress testing and loss-counter
monitoring.

Power and USB requirements
==========================

The default build selects ``PWR_LDO_SUPPLY``. The schematic must supply
VDDLDO and decouple VCAP according to ST's hardware guidance. For a board
using the internal SMPS, select the matching HAL supply constant, for
example::

  make BOARD=stm32h735zgt6 \
    STM32H735_SUPPLY=PWR_DIRECT_SMPS_SUPPLY

The selected mode must match the physical power topology.

By default, the internal USB regulator is disabled and the PCB must provide
the documented external VDD33USB/VDD50USB arrangement. If the board instead
feeds the internal USB regulator through VDD50USB, build with::

  make BOARD=stm32h735zgt6 \
    STM32H735_USB_INTERNAL_REGULATOR=1

Do not enable the regulator while externally driving VDD33USB. The current
BSP disables PA9 VBUS sensing and forces a valid USB device session; a
self-powered product must implement compliant VBUS-presence handling.

Flashing
========

The default flash target uses J-Link over SWD::

  make BOARD=stm32h735zgt6 flash

ST-LINK with STM32CubeProgrammer is also supported::

  make BOARD=stm32h735zgt6 flash-stlink

Expose VTref, GND, PA13/SWDIO, PA14/SWCLK, and preferably NRST. Factory ROM
USB DFU on PA11/PA12 is available when BOOT0 and option bytes select system
memory. ES0491 notes that ROM USB DFU is not functional at RDP level 1. This
target does not provide a custom SuperDFU bootloader.

H735-specific difference
========================

STM32H735 adds CRYP, HASH, and OTFDEC hardware. Its vector table therefore
has handlers that are absent or reserved on STM32H725. SuperCAN does not use
those peripherals, but the dedicated H735 build selects
``startup_stm32h735xx.s`` and ``stm32h735xx.h`` so device identity, vectors,
and programmer settings remain correct. This port does not enable or
provision CRYP, HASH, OTFDEC, secure firmware installation, or H735 security
option bytes; those features require a separate product security design.
ES0491 states that secure firmware installation is not supported on the
listed H735 revisions. Review both ES0491 and SA0053 before using OTFDEC or
the associated root secure services.

References
==========

* `STM32H735xG datasheet <https://www.st.com/resource/en/datasheet/stm32h735ig.pdf>`_
* `STM32H735ZG product page <https://www.st.com/en/microcontrollers-microprocessors/stm32h735zg.html>`_
* `AN5419 hardware development guide <https://www.st.com/resource/en/application_note/an5419-getting-started-with-stm32h723733-stm32h725735-and-stm32h730-mcu-hardware-development-stmicroelectronics.pdf>`_
* `RM0468 reference manual <https://www.st.com/resource/en/reference_manual/dm00603761.pdf>`_
* `ES0491 device errata <https://www.st.com/resource/en/errata_sheet/es0491-stm32h72xx73xx-device-errata-stmicroelectronics.pdf>`_
* `SA0053 security advisory <https://www.st.com/resource/en/security_advisory/sa0053-arbitrary-code-execution-with-privilege-on-stm32h73xxx-and-stm32h7bxxx-microcontrollers-stmicroelectronics.pdf>`_
* `ST FDCAN clock guidance <https://community.st.com/t5/stm32-mcus/faq-fixing-stm32-fdcan-communication-disruptions-apb-bus-kernel/ta-p/730298>`_

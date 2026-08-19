STM32H725ZGT6 custom target
===========================

This firmware target is a baseline for a custom board using the 1 MiB,
LQFP144 STM32H725ZGT6. It is not a pin-compatible replacement for the
NUCLEO-H7A3ZI-Q and it does not describe a complete PCB. The target exposes
one, two, or three independent SuperCAN channels. Channel 0 uses FDCAN1,
optional channel 1 uses FDCAN2, and optional channel 2 uses FDCAN3.

**Each channel requires its own external CAN-FD transceiver. Never connect
PB5, PB6, PB8, PB9, PG9, or PG10 directly to CANH or CANL.**

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

``STM32H725_FDCAN_COUNT`` accepts ``1``, ``2``, or ``3`` and defaults to ``2``
when omitted. To build single- or three-channel images instead::

  make BOARD=stm32h725zgt6 STM32H725_FDCAN_COUNT=1
  make BOARD=stm32h725zgt6 STM32H725_FDCAN_COUNT=3

The default clock source is the internal HSI64 oscillator. To build for a
25 MHz external crystal instead::

  make BOARD=stm32h725zgt6 STM32H725_USE_HSE=1

``STM32H725_USE_HSE`` accepts exactly ``0`` or ``1`` and defaults to ``0``.
It can be combined with any supported ``STM32H725_FDCAN_COUNT`` value.

The two-channel build creates ``_build/stm32h725zgt6/supercan.elf``,
``supercan.hex``, and ``supercan.bin``. The single- and three-channel outputs
are kept in ``_build/stm32h725zgt6-fdcan1`` and
``_build/stm32h725zgt6-fdcan3`` respectively, so changing the flag cannot
reuse objects from another configuration. The image is linked for the start
of internal flash at ``0x08000000``. The target can be flashed over SWD with
the ``flash-jlink`` or ``flash-stlink`` make targets. ST's factory USB DFU
bootloader is another option when the PCB boot configuration supports it;
SuperDFU is not provided for this target.

HSE builds use separate output directories. The one-, two-, and three-channel
paths are ``_build/stm32h725zgt6-fdcan1-hse25``,
``_build/stm32h725zgt6-hse25``, and
``_build/stm32h725zgt6-fdcan3-hse25`` respectively.

The channel count also controls the USB configuration: the image exposes one
SuperCAN vendor interface per enabled FDCAN channel. The release script
explicitly builds the default two-channel HSI image with
``STM32H725_USE_HSE=0`` and packages it from ``_build/stm32h725zgt6``. Build
the optional channel counts and HSE images directly with the commands above.

Default signal map
==================

The target places FDCAN1 and FDCAN2 on GPIOB and FDCAN3 on GPIOG:

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
| FDCAN3 RX            | PG10     | 123        | AF2; connect from CAN-FD transceiver RXD      |
+----------------------+----------+------------+-----------------------------------------------+
| FDCAN3 TX            | PG9      | 122        | AF2; connect to CAN-FD transceiver TXD        |
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

PB5/PB6 are configured for FDCAN2 when ``STM32H725_FDCAN_COUNT`` is ``2`` or
``3``. PG10/PG9 are configured for FDCAN3 only when the count is ``3``. Builds
that do not select those channels leave their pins in the reset state for
other board functions. If an unused CAN transceiver is populated, hold it in
standby or provide a pull that keeps its TXD input recessive.

The LED and button assignments are firmware defaults, not fixed features of
the MCU. Change them in the target BSP if the custom PCB uses other pins. The
default mapping provides status LEDs for channel 0 only; channels 1 and 2
operate without dedicated status LEDs. The firmware does not define
transceiver enable or standby GPIOs, so the PCB must strap those inputs for
normal operation or extend the target with control pins.

Clock and memory configuration
==============================

The default board support package uses only internal oscillators:

* HSI64 and PLL1 produce a 120 MHz system and AXI clock:
  ``64 MHz / 4 * 15 / 2 = 120 MHz``.
* HSI48 supplies the 48 MHz USB kernel clock.
* PLL2 Q supplies an 80 MHz FDCAN kernel clock:
  ``64 MHz / 4 * 15 / 3 = 80 MHz``. The shared CCU divides it by two to a
  40 MHz FDCAN time-quanta clock, which is strictly below the 60 MHz APB1
  clock as required by ST's FDCAN clock guidance.
* TIM2 is a free-running 1 MHz SuperCAN timestamp counter.
* The linker describes 1 MiB internal flash and the STM32H725's 560 KiB of
  normal SRAM. Initialized data, RAM-resident code, BSS, heap, and stack stay
  inside the first 128 KiB of AXI SRAM, which exists for every supported
  ITCM/AXI option-byte split.

The additional 192 KiB ``AXIRAM_EXT`` linker region is available in full only
with the default 64 KiB ITCM / 320 KiB AXI SRAM option-byte split. The firmware
does not place anything there automatically. Verify the option bytes before
assigning custom sections to that region.

**Optional 25 MHz HSE crystal.** ``STM32H725_USE_HSE=1`` selects crystal mode
for a 25 MHz crystal or ceramic resonator connected between PH0-OSC_IN
(LQFP144 pin 25) and PH1-OSC_OUT (LQFP144 pin 26). The BSP requests
``RCC_HSE_ON``; it does not select HSE bypass mode and therefore is not the
configuration for a driven external clock input.

Choose the resonator and its load network from the resonator manufacturer's
data and ST's `AN2867 oscillator design guide
<https://www.st.com/resource/en/application_note/an2867-oscillator-design-guide-for-stm8afals-stm32-mcus-and-mpus-stmicroelectronics.pdf>`_.
Account for PCB and pin stray capacitance, place the resonator network close
to the MCU, and validate startup margin and drive level on the actual PCB.
There is no universal load-capacitor value suitable for every crystal and
layout.

The HSE build uses a 5 MHz PLL input and legal 240 MHz wide-range VCOs. PLL1
produces SYSCLK as ``25 MHz / 5 * 48 / 2 = 120 MHz``. PLL2 Q produces an
80 MHz FDCAN kernel clock as ``25 MHz / 5 * 48 / 3 = 80 MHz``; the CCU
divider produces the 40 MHz time-quanta clock. USB continues to use the
independent HSI48 oscillator.

Clock initialization occurs before the BSP starts a HAL tick source. If the
crystal is absent or does not start, the HAL can remain in its HSE-ready
polling loop and firmware does not reach USB or SuperCAN. A HAL-reported
oscillator or PLL configuration error enters the BSP failure loop. There is no
automatic fallback from an HSE build to the internal-clock configuration.

FDCAN1, FDCAN2, and FDCAN3 share one fixed 10 KiB CAN message RAM. The one-
and two-channel modes use 32 transmit FIFO and 32 transmit-event elements per
enabled controller. The single-channel mode restores the hardware maximum of
64 receive elements and uses this layout::

  0x0000 - 0x1bff  FDCAN1: 7,168 bytes
  0x1c00 - 0x27ff  Unused:  3,072 bytes

The two-channel mode uses 32 receive elements per controller and partitions
the message RAM as follows::

  0x0000 - 0x12ff  FDCAN1: 4,864 bytes
  0x1300 - 0x25ff  FDCAN2: 4,864 bytes
  0x2600 - 0x27ff  Unused:    512 bytes

The three-channel mode keeps 32 receive elements per controller, reduces each
hardware transmit and transmit-event FIFO to 12 elements, and uses this
receive-biased partition::

  0x0000 - 0x0cbf  FDCAN1: 3,264 bytes
  0x0cc0 - 0x197f  FDCAN2: 3,264 bytes
  0x1980 - 0x263f  FDCAN3: 3,264 bytes
  0x2640 - 0x27ff  Unused:    448 bytes

The regions are offsets from ``SRAMCAN_BASE`` and do not overlap. The hardware
message RAM cannot be enlarged or relocated into normal SRAM. SuperCAN also
maintains per-channel software queues in normal SRAM and drains the smaller
hardware transmit FIFOs from the interrupt handlers. The target disables
FDCAN edge filtering as required by STM32H725 erratum ES0491 section 2.22.1.

All enabled CAN channels share the 12 Mbit/s USB full-speed link. Multi-channel
operation does not guarantee lossless capture when the CAN-FD buses are
simultaneously near their maximum configured load; validate aggregate
throughput for the application and monitor the SuperCAN loss counters. The
USB controller has enough endpoints for three channels, but endpoint capacity
does not increase the link bandwidth.

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
* `ST FDCAN clock guidance <https://community.st.com/t5/stm32-mcus/faq-fixing-stm32-fdcan-communication-disruptions-apb-bus-kernel/ta-p/730298>`_
* `RM0468: STM32H723/733, STM32H725/735, and STM32H730 reference manual <https://www.st.com/resource/en/reference_manual/dm00603761.pdf>`_
* `STM32H725ZG product page <https://www.st.com/en/microcontrollers-microprocessors/stm32h725zg.html>`_

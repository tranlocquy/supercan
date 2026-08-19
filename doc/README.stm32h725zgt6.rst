STM32H725ZGT6 custom target
===========================

This firmware target is a baseline for a custom board using the 1 MiB,
LQFP144 STM32H725ZGT6. It is not a pin-compatible replacement for the
NUCLEO-H7A3ZI-Q and it does not describe a complete PCB.

**An external CAN-FD transceiver is required. Never connect PD0 or PD1
directly to CANH or CANL.**

Build target
============

Use ``BOARD=stm32h725zgt6``. From the SuperCAN repository root::

  git submodule update --init Boards
  git -C Boards submodule update --init \
    lib/CMSIS_5 lib/FreeRTOS-Kernel \
    hw/mcu/st/cmsis_device_h7 \
    hw/mcu/st/stm32h7xx_hal_driver
  cd Boards/examples/device/supercan
  make BOARD=stm32h725zgt6

The build creates ``_build/stm32h725zgt6/supercan.elf``, ``supercan.hex``,
and ``supercan.bin``. The image is linked for the start of internal flash at
``0x08000000``. The target can be flashed over SWD with the ``flash-jlink`` or
``flash-stlink`` make targets. ST's factory USB DFU bootloader is another
option when the PCB boot configuration supports it; SuperDFU is not provided
for this target.

Default signal map
==================

The target deliberately keeps the logical GPIO choices of the original H7A3
port where those signals also exist on STM32H725ZGT6:

+----------------------+----------+------------+-----------------------------------------------+
| Function             | Signal   | LQFP144 pin| Configuration                                 |
+======================+==========+============+===============================================+
| FDCAN1 RX            | PD0      | 112        | AF9; connect from CAN-FD transceiver RXD      |
+----------------------+----------+------------+-----------------------------------------------+
| FDCAN1 TX            | PD1      | 113        | AF9; connect to CAN-FD transceiver TXD        |
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
| CAN green LED        | PB0      | 49         | Push-pull output, active high                 |
+----------------------+----------+------------+-----------------------------------------------+
| CAN red LED          | PB14     | 74         | Push-pull output, active high                 |
+----------------------+----------+------------+-----------------------------------------------+
| User button          | PC13     | 9          | Input, no internal pull, active high          |
+----------------------+----------+------------+-----------------------------------------------+

The LED and button assignments are firmware defaults, not fixed features of
the MCU. Change them in the target BSP if the custom PCB uses other pins. The
firmware does not define a transceiver enable or standby GPIO, so the PCB must
strap those inputs for normal operation or extend the target with a control
pin.

Clock and memory configuration
==============================

The default board support package uses only internal oscillators:

* HSI64 and PLL1 produce a 120 MHz system and AXI clock.
* HSI48 supplies the 48 MHz USB kernel clock.
* PLL2 Q supplies an 80 MHz FDCAN kernel clock.
* TIM2 is a free-running 1 MHz SuperCAN timestamp counter.
* The linker describes 1 MiB internal flash and the STM32H725's 560 KiB of
  normal SRAM. Initialized data, RAM-resident code, BSS, heap, and stack stay
  inside the first 128 KiB of AXI SRAM, which exists for every supported
  ITCM/AXI option-byte split.

The additional 192 KiB ``AXIRAM_EXT`` linker region is available in full only
with the default 64 KiB ITCM / 320 KiB AXI SRAM option-byte split. The firmware
does not place anything there automatically. Verify the option bytes before
assigning custom sections to that region.

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
* `AN4879: USB hardware and PCB guidelines <https://www.st.com/resource/en/application_note/an4879-usb-hardware-and-pcb-guidelines-using-stm32-mcus-stmicroelectronics.pdf>`_
* `STM32H725ZG product page <https://www.st.com/en/microcontrollers-microprocessors/stm32h725zg.html>`_

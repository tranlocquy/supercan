# SuperCAN STM32H7 Firmware Reverse-Engineering Notes

## Scope

This report documents the STM32H7 target present in this fork at the revision below:

- Repository branch: `tranlocquy/supercan:reverse-engineer`
- Analyzed base commit: `0212434a1de090e7fa3f28c8e1d792e25d49fd1e`
- Pinned `Boards` (`jgressmann/tinyusb`) commit: `b7ea92b22f632e5030dc7e5be0c4fc9377e6421f`
- Analysis date: 2026-08-18

The SuperCAN STM32H7 build target is specifically `BOARD=stm32h7a3nucleo`: the ST **NUCLEO-H7A3ZI-Q**, main board **MB1363-H7A3ZIQ-D01**, populated with an **STM32H7A3ZIT6Q**. The generic H743/H745/H755 TinyUSB BSP directories in the submodule are not selected by this SuperCAN target.

## Executive summary

- One CAN-FD controller is exposed to the host: **FDCAN1**, SuperCAN channel 0.
- **PD1** is `FDCAN1_TX`; **PD0** is `FDCAN1_RX`.
- Both pins use STM32 alternate function **AF9**.
- The firmware configures an 80 MHz FDCAN kernel clock from PLL2 Q.
- The Nucleo board exposes only the MCU-side logic signals. An external CAN-FD transceiver is required.
- No transceiver standby or enable GPIO is defined by this firmware.

## CAN interface and connector mapping

| Function | MCU GPIO | AF | MCU package pin | Populated ST Zio header | Optional ST Morpho header |
|---|---|---:|---:|---|---|
| FDCAN1 RX | PD0 | AF9 | U14 pin 112 | **CN9 pin 25**, D67 / CAN_RX | CN11 pin 57 |
| FDCAN1 TX | PD1 | AF9 | U14 pin 113 | **CN9 pin 27**, D66 / CAN_TX | CN11 pin 55 |
| Ground | - | - | - | **CN9 pin 23** | Multiple GND pins |

`CN9` is the convenient connection because it is populated. The CN11/CN12 Morpho headers are footprints that are not populated by default.

### Recommended logic-side wiring

```text
NUCLEO CN9-27 / PD1 / FDCAN1_TX  --->  CAN-FD transceiver TXD
NUCLEO CN9-25 / PD0 / FDCAN1_RX  <---  CAN-FD transceiver RXD
NUCLEO CN9-23 / GND               <-->  CAN-FD transceiver GND

CAN-FD transceiver CANH/CANL      <-->  Physical CAN bus
```

PD0 and PD1 are 3.3 V MCU logic signals; they are **not** CANH and CANL. Use a CAN-FD-capable transceiver whose MCU interface is 3.3 V compatible, or one with `VIO` powered at 3.3 V. Power the transceiver according to its datasheet. Strap its mode/standby pins for normal operation because this firmware has no GPIO for them. Fit 120 ohm termination only when this node is at a physical end of the bus.

## GPIO inventory

The selected build actively configures 11 unique MCU GPIO pins:

| Subsystem | Pin | Configuration | Board connection / behavior |
|---|---|---|---|
| FDCAN1 RX | PD0 | AF9, alternate-function mode | CN9-25 / D67; input from transceiver RXD |
| FDCAN1 TX | PD1 | AF9, alternate-function mode | CN9-27 / D66; output to transceiver TXD |
| CAN status LED | PB0 | Push-pull output, active high | Green user LED LD1; CAN0 green state |
| Debug/status LED | PE1 | Push-pull output, active high | Yellow user LED LD2; debug/boot indication |
| CAN error LED | PB14 | Push-pull output, active high | Red user LED LD3; CAN0 red/error state |
| User button | PC13 | Input, no internal pull, active high | Blue B1 button; BSP initializes it, but SuperCAN does not appear to read it |
| Debug UART TX | PD8 | USART3 TX, AF7, pull-up | Routed to ST-LINK virtual COM by default |
| Debug UART RX | PD9 | USART3 RX, AF7, pull-up | Routed to ST-LINK virtual COM by default |
| USB ID | PA10 | AF10, open-drain, pull-up | Target USB connector CN13 |
| USB D- | PA11 | AF10, no pull | Target USB connector CN13 |
| USB D+ | PA12 | AF10, no pull | Target USB connector CN13 |

USART3 is initialized for 115200 baud, 8 data bits, no parity, one stop bit, and no hardware flow control.

### GPIO-related exclusions

- PA9 is physically connected to USB VBUS, but `OTG_FS_VBUS_SENSE` is zero. Its GPIO initialization is compiled out, VBUS sensing is disabled, and the firmware forces a valid B-device session.
- The USB ULPI pin group is not configured. This board selects port 0 and the USB1 OTG HS core with its internal full-speed PHY.
- TIM2 is used only as an internal 1 MHz timestamp counter; no timer channel is routed to a pin.
- GPIO clocks are enabled broadly for the BSP. Clock enable alone does not mean every pin on those ports is assigned.
- PA13/PA14 remain associated with the onboard SWD/ST-LINK debugger and should not be treated as application GPIOs.
- No FDCAN2 pins are initialized.

## Clock and peripheral initialization

### CPU and USB clocks

The board clock setup uses the internal 64 MHz HSI and HSI48 oscillators:

- PLL1: 64 MHz / 4 x 15 / 2 = **120 MHz system clock**.
- HSI48 supplies the **48 MHz USB kernel clock**.
- The active setup does not require an external HSE clock pin.

### FDCAN clock

`can_init()` configures PLL2 Q as follows:

- Input: 64 MHz HSI
- M = 4, producing 16 MHz
- N = 15
- Q = 3
- FDCAN kernel clock: 16 MHz x 15 / 3 = **80 MHz**

The code selects PLL2 Q as the FDCAN clock source, enables the FDCAN peripheral and low-power clocks, configures the clock-calibration unit in bypass mode, and enables FDCAN interrupt line 0.

### CAN message RAM

The compile-time and initialization settings are:

- 1 SuperCAN CAN channel
- 64-element hardware RX FIFO
- 32-element hardware TX FIFO
- 32-element TX event FIFO
- RX and TX elements configured for CAN-FD payloads up to 64 bytes
- FDCAN1 interrupt handled by `FDCAN1_IT0_IRQHandler()`

The message RAM layout is RX FIFO first, followed by the TX FIFO and then the TX event FIFO in `SRAMCAN`.

### Initialization order

`sc_board_init_begin()` performs the following sequence:

1. `board_init()` - clocks, generic LED/button setup, USART3, and USB.
2. `leds_init()` - PB0, PE1, and PB14 status LEDs.
3. `can_init()` - PD0/PD1, PLL2, FDCAN1, message RAM, and interrupt setup.
4. `counter_1mhz_init()` - free-running TIM2 timestamp counter.

At the end of board initialization, the yellow/debug LED is scheduled to blink and the NVIC priority grouping is configured.

## Board-level cautions

- **External transceiver required:** never connect PD0/PD1 directly to CANH/CANL.
- **Target USB connector:** SuperCAN USB data uses CN13, not the ST-LINK USB connector. The ST manual warns that CN13 does not power the Nucleo board; power the board before attaching CN13.
- **Red LED conflict:** PB14 is also exposed as Zio D65. The onboard LD3 connection loads that signal; remove the documented LED resistor if PB14 must be isolated from LD3.
- **Green LED routing:** the firmware assumes the default LD1 routing to PB0 rather than the alternate PA5 solder-bridge configuration.
- **Debug UART routing:** PD8/PD9 are connected to the embedded ST-LINK virtual COM port by default. Access through Morpho requires the applicable solder-bridge changes.
- **Morpho headers:** CN11/CN12 are unpopulated by default; use CN9 for the CAN logic signals unless headers have been fitted.

## Source trace

Firmware sources at the analyzed revisions:

- [Fork H7A3 board README](https://github.com/tranlocquy/supercan/blob/reverse-engineer/doc/README.stm32h7a3nucleo.rst)
- [SuperCAN target selection](https://github.com/jgressmann/tinyusb/blob/b7ea92b22f632e5030dc7e5be0c4fc9377e6421f/examples/device/supercan/Makefile#L66-L69)
- [H7A3 board capabilities and FIFO sizes](https://github.com/jgressmann/tinyusb/blob/b7ea92b22f632e5030dc7e5be0c4fc9377e6421f/examples/device/supercan/inc/supercan_stm32h7a3nucleo.h#L10-L37)
- [FDCAN GPIO, clock, RAM, LED, timer, and interrupt initialization](https://github.com/jgressmann/tinyusb/blob/b7ea92b22f632e5030dc7e5be0c4fc9377e6421f/examples/device/supercan/src/supercan_stm32h7a3nucleo.c#L95-L218)
- [H7A3 LED, button, UART, and USB board definitions](https://github.com/jgressmann/tinyusb/blob/b7ea92b22f632e5030dc7e5be0c4fc9377e6421f/hw/bsp/stm32h7/boards/stm32h7a3nucleo/board.h#L14-L39)
- [STM32H7 BSP GPIO and USB initialization](https://github.com/jgressmann/tinyusb/blob/b7ea92b22f632e5030dc7e5be0c4fc9377e6421f/hw/bsp/stm32h7/family.c#L138-L214)
- [H7A3 USB port/PHY build selection](https://github.com/jgressmann/tinyusb/blob/b7ea92b22f632e5030dc7e5be0c4fc9377e6421f/hw/bsp/stm32h7/boards/stm32h7a3nucleo/board.mk#L1-L6)

ST hardware references:

- [UM2408 - STM32H7 Nucleo-144 boards (MB1363) user manual](https://www.st.com/resource/en/user_manual/um2408-stm32h7-nucleo144-boards-mb1363-stmicroelectronics.pdf)
- [MB1363-H7A3ZIQ-D01 schematic](https://www.st.com/resource/en/schematic_pack/mb1363-h7a3ziq-d01_schematic.pdf)
- [DS13195 - STM32H7A3xI/G datasheet](https://www.st.com/resource/en/datasheet/stm32h7a3vi.pdf)

## Revision note

This is a static reverse-engineering report for the commits listed in the Scope section. Re-check the board submodule and initialization sources if the fork is later synchronized with upstream.

The later `STM32H725xx` branch adds a custom-board port for STM32H725ZGT6. Its implementation assumptions, complete default pin map, power choices, and build instructions are documented in [doc/README.stm32h725zgt6.rst](doc/README.stm32h725zgt6.rst); they are not properties of the original NUCLEO-H7A3ZI-Q firmware analyzed above.

The `2FDCAN` branch extends that custom target with a selectable FDCAN count. The later `3FDCAN` branch accepts `STM32H725_FDCAN_COUNT=1|2|3`: channel 0 uses FDCAN1 on PB8/PB9, optional channel 1 uses FDCAN2 on PB5/PB6, and optional channel 2 uses FDCAN3 on PF6/PF7. All enabled controllers share the STM32H725's fixed 10 KiB CAN message RAM, so the three-channel build uses smaller per-controller hardware transmit FIFOs.

; ***
; HD44780 LCD Driver for ATmega2560.
; (DFRobot LCD Keypad Shield v1.1, Arduino Mega2560)
;
; Title: 		LCD.asm
; Description: 	LCD Configuration and Subroutines
; Author: 		Keegan van der Laag (jkvander@uvic.ca)
; Updated:		23 February 2015
;
; Modified:		B. Bird - 17 June 2017
; 				This version contains only the definitions
; 				needed by the LCD functions (which are in the
;				separate lcd_function_code.asm file).


; ---
;
; Some code shamelessly adapted from the C implementation of an HD44780
; driver by Peter Dannegger, posted to the AVR Freaks forum. The original
; driver is available here:
;
; http://www.avrfreaks.net/forum/tutc-lcd-tutorial-1001?name=PNphpBB2&file=viewtopic&t=102296
; 
; Delay loops hackishly paraphrased from Atmel's AVR C libraries.
;
; This module provides configuration, initialization, and control
; routines for a Hitachi HD44780-compatible LCD controller connected
; to an Atmel AVR microcontroller unit. It makes the following asusmptions:
; 	- The R/W pin on the HD44780 is permanently grounded, making it
;	  impossible to read the busy flag from the controller.
;	- Similarly, the DDRAM and CGRAM addresses cannot be read from the
;	  controller, meaning that the cursor position must be manually tracked
;	  and updated to match the LCD if cursor position is important to you.
;	- The HD44780 is being operated in 4-bit mode rather than 8-bit.
;	- Only one HD44780 is connected. (No ridiculously large matrices of 
;	  characters.)
;
; Also, the busy-wait delays used for the timing of LCD initialization and
; commands currently assume that the AVR MCU is running at 16 MHz. This is
; by laziness, not by design; it will be corrected in a future version.
;
; This module #includes a definition file for an unwieldy and sizable number
; of LCD-related symbols and values. This file is called LCDdefs.inc, and
; should be located in the project directory with this module, or in the
; main include directory of your AVR Toolchain installation.
;
; When including this module in your project, it is important to #define
; the symbol LCD_LIB_ONLY to keep this file from trying to run the default
; initialization and program loop written into the driver.
;
; LCD pin and port assignment, as well as setting things like LCD size in
; columns and rows, and the collection of HD44780 display modes and settings,
; can be done either here in the header #defines, or in the header of the
; program including the driver. In order for the program to assemble, the
; following symbols must be defined, as well as their listed children:
;
;	LCD_SIZE
;		LCD_ROW 				(n = 1, 2, 4)
;		LCD_COLUMN				(n = 8, 12, 16, 20, 24, 40)
;	LCD_DISPLAY_SET
;		LCD_SHOW_CURSOR			(n = 0, 1)
;		LCD_BLINK_CURSOR		(n = 0, 1)
;		LCD_DISPLAY_ON			(n = 0, 1)
;	LCD_INTERFACE_SET
;		LCD_INTERFACE_WIDTH		(n = 0, 1)
;		LCD_LINE_COUNT			(n = 0, 1)
;		LCD_FONT_SIZE			(n = 0, 1)
;	LCD_CURSOR SET
;		LCD_CURSOR_DIR			(n = 0, 1)
;		LCD_DISPLAY_SHIFT		(n = 0, 1)
;	LCD_SHIFT_SET
;		LCD_MOVE_SHIFT			(n = 0, 1)
;		LCD_SHIFT_DIR			(n = 0, 1)
;	LCD_INTERFACE_PORTS
;		LCD_PORT_D4				All LCD ports must be set using .equ
;		LCD_PORT_D5				rather than #define, and must be the
;		LCD_PORT_D6				memory address of an I/O port.
;		LCD_PORT_D7				This uses values from your Atmel partdef
;		LCD_PORT_RS				include, and so I/O space offset does not
;		LCD_PORT_ENA			need to be applied. Use of .equ is for
;								compatibility with Atmel's partdefs. Use 
;								the defaults provided here as an example.
;		LCD_PIN_D4
;		LCD_PIN_D5
;		LCD_PIN_D6				Pins are bit numbers within a port,
;		LCD_PIN_D7				(0 <= n <= 7)
;		LCD_PIN_RS
;		LCD_PIN_ENA
;
; Wherever possible, if something is defined in the including program, I've
; tried to have this driver defer to those definitions. Similarly, if there's
; anywhere something isn't defined and it should be, I've attempted to have the
; driver spit out a helpful assembler error. By and large, if an entire block of
; things is not defined, the driver will use default values. (Pin assignments,
; LCD size, display modes and settings, etc.) If individual values are not defined
; (for instance, a specific port or pin, LCD rows but not columns, Display mode
; but not whether to show/hide the cursor, etc) the assembler will error and tell
; you to define them. It should also do a pretty good job of letting you know if
; you've accidentally set an LCD size that isn't supported by the HD44780
;
; To this end, there is a LOT of conditional assembly here, which is why I've tried
; to do most of it in the included definitions file. If you want to make changes
; to the way the LCD behaves by default, it can be done using the settings in this
; module's header. You shouldn't need to modify anything in LCDdefs.inc, unless I've
; done something really, heinously wrong.

; The lcd_putchar/lcd_puts routines should include functionality for
; automatically updating the cursor row/column values stored in memory,
; as well as automatically overflowing to the next line if necessary. For
; application reasons, this version of the driver has this functionality
; removed.

; End Notes
; ***

; If no partdef file has been included yet, include the partdef for
; the ATmega2560.
.ifndef SIGNATURE_000
.include "m2560def.inc"
.endif


; Define the LCD size in rows x columns. Constants are conditionally
; determined based on this, and should be compatible with any HD44780
; controlled display.
#ifndef LCD_SIZE
#define LCD_SIZE
#message "LCD_SIZE not set, using default values."

	#define LCD_ROW			2
	#define LCD_COLUMN		16

#endif


#ifndef LCD_DISPLAY_SET
#define LCD_DISPLAY_SET
#message "LCD_DISPLAY_SET not set, using default values."

	#define LCD_SHOW_CURSOR		0	; Show cursor = 1, Hide cursor = 0
	#define LCD_BLINK_CURSOR	0	; Blink on = 1, off = 0
	#define LCD_DISPLAY_ON		1	; Entire Display On = 1, Off = 0

#endif


#ifndef LCD_CURSOR_SET
#define LCD_CURSOR_SET
#message "LCD_CURSOR_SET not set, using default values."

	#define LCD_CURSOR_DIR		1	; Increment = 1, Decrement = 0
	#define LCD_DISPLAY_SHIFT	0	; Display shift on = 1, off = 0

#endif


#ifndef LCD_INTERFACE_SET
#define LCD_INTERFACE_SET
#message "LCD_INTERFACE_SET not set, using default values."

	#define LCD_INTERFACE_WIDTH	0	; 4-bit = 0, 8-bit = 1
	#define LCD_LINE_COUNT		1	; 1 line = 0, 2 lines = 1
	#define LCD_FONT_SIZE		0	; 5x8 dot = 0, 5x10 dot = 1

#endif


#ifndef LCD_SHIFT_SET
#define LCD_SHIFT_SET
#message "LCD_SHIFT_SET not set, using default values."

	#define LCD_MOVE_SHIFT		0	; Move cursor = 0, Shift display = 1
	#define LCD_SHIFT_DIR		0	; Shift left = 0, Shift right = 1

#endif


; ***
; LCD Pin Definitions.
; Changing these should affect lcd_init, lcd_nbl, lcd_byte, and lcd_putchar
; These default assignments are for the Arduino Mega2560 with DFRobot LCD
; Keypad Shield. Symbols used must be defined in the Atmel AVR partdef file
; used, or you're going to have a bad time.

.ifndef LCD_INTERFACE_PORTS
.set LCD_INTERFACE_PORTS = 1
.message "LCD_INTERFACE_PORTS not set, using default values."

.equ	LCD_PORT_D4  =  PORTG
.equ	LCD_PORT_D5  =	PORTE
.equ	LCD_PORT_D6  =	PORTH
.equ	LCD_PORT_D7  =	PORTH

.equ	PIN_D4	  =		5
.equ	PIN_D5	  =		3
.equ	PIN_D6	  =		3
.equ	PIN_D7	  =		4

.equ	LCD_PORT_ENA =	PORTH
.equ 	LCD_PORT_RS  =	PORTH

.equ	PIN_ENA	  =		6
.equ	PIN_RS	  =		5
.endif

; ***
; End of LCD Pin Definitions


#define LCD_LIBONLY

; ***
; Include LCD Driver Constants and Conditionals.
.include "LCDdefs.inc"
; ***

#define LCD_DEFS_INCLUDED

/* CSC230.h
   CSC 230 - Summer 2017
   
   A header file to agglomerate the various definitions
   needed to compile C programs for the ATmega2560 board.

   Some of the code below is due to other authors, including
   Peter Dannegger and the designers of the processor and LCD shield.   
   
   In your code, it should suffice to use the line
	#include "CSC230.h"
   instead of manually including all of the component files.
   
   B. Bird - 07/04/2017
*/

#ifndef CSC230_H
#define CSC230_H

//Define the clock speed of the CPU to be 16Mhz
#define F_CPU 16000000UL

#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>

// Due to Peter Dannegger
// Macro to access particular bits of a 1-byte value like variables
// (e.g. to read bit 3 of a value x, use SBIT(x,3), and to write to 
//  bit 3, use a statement like 'SBIT(x,3) = 1')
struct bits {
  uint8_t b0:1, b1:1, b2:1, b3:1, b4:1, b5:1, b6:1, b7:1;
} __attribute__((__packed__));
#define SBIT_(port,pin) ((*(volatile struct bits*)&port).b##pin)
#define	SBIT(x,y)       SBIT_(x,y)






// Define the constant LCD_2X16 and set up the LCD for 2 line, 16 column mode
#define LCD_2X16

#define LCD_COLUMN      16
#define LCD_LINE        2
#define LCD_LINE1       0x80
#define LCD_LINE2       (0x80 + 0x40)


// Definitions to set up the port and pin numbers for the LCD interface
// (used by the LCD functions).
#define	LCD_D4		SBIT( PORTG, 5 )
#define	LCD_DDR_D4	SBIT( DDRG, 5 )

#define	LCD_D5		SBIT( PORTE, 3 )
#define	LCD_DDR_D5	SBIT( DDRE, 3 )

#define	LCD_D6		SBIT( PORTH, 3 )
#define	LCD_DDR_D6	SBIT( DDRH, 3 )

#define	LCD_D7		SBIT( PORTH, 4 )
#define	LCD_DDR_D7	SBIT( DDRH, 4 )

#define	LCD_RS		SBIT( PORTH, 5 )
#define	LCD_DDR_RS	SBIT( DDRH, 5 )

#define	LCD_E0		SBIT( PORTH, 6 )
#define	LCD_DDR_E0	SBIT( DDRH, 6 )


/* LCD timing constants */

#define	LCD_TIME_ENA    1.0             // 1µs
#define LCD_TIME_DAT    50.0            // 50µs
#define LCD_TIME_CLR    2000.0          // 2ms

/* LCD function declarations */

void lcd_putchar( uint8_t d );
void lcd_init( void );
void lcd_puts( void *s );
void lcd_blank( uint8_t len );          // blank n digits
void lcd_command( uint8_t d );

// An inline function to set the x and y position
// in a 2-line LCD display
static inline void lcd_xy(uint8_t x, uint8_t y){
	lcd_command(x + ((y==1) ? LCD_LINE2 : LCD_LINE1 ));
}


#endif


; a03.asm
; Name: Jorge Fernando Flores Pinto
; ID: V00880059
; CSC230, Summer 2017
;
; This .asm was built from Bill's starter code. I also used some of his code (from Lectures or Labs)
; to aid me through the implementation of some functionalities (such as copying strings, displaying
; on the LCD, and interrupts). I've kept some of his comments in the code as well.
;
; This .asm is a timer. It also has the feature of keeping lap times.

.equ SPH_DATASPACE = 0x5E
.equ SPL_DATASPACE = 0x5D

.equ STACK_INIT = 0x21FF

.def D0 = r17
.def D1 = r18
.def D2 = r19
.def D3 = r20
.def IGNORE_BUTTON = r21
.def INTERRUPT_FLAG = r22
.def OVERFLOW_COUNTER = r23
.def BUTTON_PRESSED = r24
.def SPEED = r25

; The loop itself will count down to 0 from a 32-bit
; constant. Just like the low() and high() macros
; for breaking up 16-bit numbers into bytes, we can
; use low(), byte2(), byte3() and byte4() to break
; up a 32-bit value into four bytes (with byte4() being
; the most-significant)
.equ counter_value = 0x0003FC18
; Define the four initial bytes as constants
; Note that we subtract one since the loop below has the form
; while(D3:D0 >= 0) (so D3:D0 will actually equal 0 on one iteration)
.equ CV0 = low(counter_value-1)
.equ CV1 = byte2(counter_value-1)
.equ CV2 = byte3(counter_value-1)
.equ CV3 = byte4(counter_value-1)


.include "m2560def.inc"

.include "lcd_function_defs.inc"

; Definitions for button values from the ADC
; Some boards may use the values in option B
; The code below used less than comparisons so option A should work for both
; Option A (v 1.1)
;.equ ADC_BTN_RIGHT = 0x032
;.equ ADC_BTN_UP = 0x0FA
;.equ ADC_BTN_DOWN = 0x1C2
;.equ ADC_BTN_LEFT = 0x28A
;.equ ADC_BTN_SELECT = 0x352

; Option B (v 1.0)
.equ ADC_BTN_RIGHT = 0x032
.equ ADC_BTN_UP = 0x0C3
.equ ADC_BTN_DOWN = 0x17C
.equ ADC_BTN_LEFT = 0x22B
.equ ADC_BTN_SELECT = 0x316



.cseg
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                          Reset/Interrupt Vectors                            ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.org 0x0000 ; RESET vector
	jmp main_begin
	
; The interrupt vector for timer 2 overflow is 0x1e
.org 0x001e
	jmp TIMER2_OVERFLOW_ISR

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                               Main Program                                  ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; According to the datasheet, the last interrupt vector has address 0x0070, so the first
; "unreserved" location is 0x0072
.org 0x0072

main_begin:
	clr OVERFLOW_COUNTER
	clr IGNORE_BUTTON
	clr SPEED
	clr YH
	clr YL
	clr XH
	clr XL

	ldi r16, '0'
	sts TIME, r16
	sts (TIME+1), r16
	sts (TIME+2), r16
	sts (TIME+3), r16
	sts (TIME+4), r16

	call INITIALIZE_LAPS

	ldi r16, 1
	sts PAUSING, r16

	clr r16
	clr r17
	clr r18
	clr r19
	clr r20
	clr r21
	clr r22


	ldi r17, 1
	ldi SPEED, 60

	; Initialize the stack
	; Notice that we use "SPH_DATASPACE" instead of just "SPH" for our .def
	; since m2560def.inc defines a different value for SPH which is not compatible
	; with STS.
	ldi r16, high(STACK_INIT)
	sts SPH_DATASPACE, r16
	ldi r16, low(STACK_INIT)
	sts SPL_DATASPACE, r16
	
	; Set up the ADC
	
	; Set up ADCSRA (ADEN = 1, ADPS2:ADPS0 = 111 for divisor of 128)
	ldi	r16, 0x87
	sts	ADCSRA, r16
	
	; Set up ADCSRB (all bits 0)
	ldi	r16, 0x00
	sts	ADCSRB, r16
	
	; Set up ADMUX (MUX4:MUX0 = 00000, ADLAR = 0, REFS1:REFS0 = 1)
	ldi	r16, 0x40
	sts	ADMUX, r16

	ldi	r22, low(ADC_BTN_SELECT)
	ldi	r23, high(ADC_BTN_SELECT)
	
	ldi r16, 0
	sts OVERFLOW_INTERRUPT_COUNTER, r16
	
	call TIMER2_SETUP ; Set up timer 2 control registers (function below)
	
	sei ; Set the I flag in SREG to enable interrupt processing
	
	; Initialize the LCD
	call lcd_init	
	
	; Load the base address of the LINE_ONE array
	ldi YL, low(LINE_ONE)
	ldi YH, high(LINE_ONE)

	; Setting up first line to print on the LCD
	
	ldi r18, 'T'
	st Y+, r18
	ldi r18, 'i'
	st Y+, r18
	ldi r18, 'm'
	st Y+, r18
	ldi r18, 'e'
	st Y+, r18
	ldi r18, ':'
	st Y+, r18
	ldi r18, ' '
	st Y+, r18

	lds r18, TIME
	st Y+, r18

	lds r18, (TIME+1)
	st Y+, r18

	ldi r18, ':'
	st Y+, r18

	lds r18, (TIME+2)
	st Y+, r18

	lds r18, (TIME+3)
	st Y+, r18

	ldi r18, '.'
	st Y+, r18

	lds r18, (TIME+4)
	st Y+, r18

	ldi r18, '0'

	
	st -Y, r18

	adiw YL, 1

	; Null terminator
	ldi r20, 0
	st Y+, r20
	st Y, r20

	sbiw YL, 2

	call SET_LCD
	call DISPLAY_STRING



button_test_loop:
	; Start an ADC conversion
	
	; Set the ADSC bit to 1 in the ADCSRA register to start a conversion
	lds	r16, ADCSRA
	ori	r16, 0x40
	sts	ADCSRA, r16

main_loop:
	
	lds	r16, ADCSRA
	andi r16, 0x40
	brne main_loop

	call right_pressed
	nop

	call up_pressed
	nop

	call down_pressed
	nop

	call left_pressed
	nop

	call select_pressed
	nop
	
	call none_pressed
	nop

	cpi BUTTON_PRESSED, 0
	breq skip

	call DELAY_FUNCTION

	cpi IGNORE_BUTTON, 1
	breq button_test_loop

	cpi IGNORE_BUTTON, 1
	breq button_test_loop

	cpi IGNORE_BUTTON, 1
	breq button_test_loop

	cpi IGNORE_BUTTON, 1
	breq button_test_loop

	cpi IGNORE_BUTTON, 1
	breq button_test_loop
	
	cpi BUTTON_PRESSED, 5
	breq set_timer

	cpi IGNORE_BUTTON, 1
	breq button_test_loop

	cpi BUTTON_PRESSED, 1
	breq skip_rigth

	cpi IGNORE_BUTTON, 1
	breq button_test_loop

	cpi BUTTON_PRESSED, 2
	breq set_lap
	
	cpi IGNORE_BUTTON, 1
	breq button_test_loop

	cpi BUTTON_PRESSED, 3
	breq clear_lap

	cpi IGNORE_BUTTON, 1
	breq button_test_loop

	cpi BUTTON_PRESSED, 4
	breq clear_timer


	rjmp button_test_loop
	
skip:
	clr IGNORE_BUTTON
	rjmp button_test_loop

skip_rigth:
	cpi IGNORE_BUTTON, 1
	breq rigth_already_pressed

	ldi IGNORE_BUTTON, 1
	rjmp button_test_loop
	
	rigth_already_pressed:
		ldi IGNORE_BUTTON, 1
		rjmp button_test_loop

set_lap:
	cpi IGNORE_BUTTON, 1
	breq lap_already_set

	cpi INTERRUPT_FLAG, 1
	breq lap_already_set

	ldi IGNORE_BUTTON, 1
	call STRCPY
	rjmp button_test_loop

	lap_already_set:
		ldi IGNORE_BUTTON, 1
		rjmp button_test_loop

clear_lap:
	cpi IGNORE_BUTTON, 1
	breq lap_already_cleared

	cpi INTERRUPT_FLAG, 1
	breq lap_already_cleared

	ldi IGNORE_BUTTON, 1
	call CLEAR_LAPS
	rjmp button_test_loop

	lap_already_cleared:
		ldi IGNORE_BUTTON, 1
		rjmp button_test_loop

clear_timer:
	cpi IGNORE_BUTTON, 1
	breq already_cleared

	ldi IGNORE_BUTTON, 1
	call SETTING_TIMER
	call SET_LCD
	call DISPLAY_STRING

	rjmp button_test_loop

	already_cleared:
		ldi IGNORE_BUTTON, 1
		rjmp button_test_loop

set_timer:
	cpi IGNORE_BUTTON, 1
	breq already_set

	lds r16, PAUSING
	cpi r16, 1
	breq unpause
	
	ldi r16, 0x00
	sts TIMSK2, r16

	ldi r16, 1
	sts PAUSING, r16

	ldi IGNORE_BUTTON, 1
	rjmp button_test_loop

	already_set:
		ldi IGNORE_BUTTON, 1
		rjmp button_test_loop

unpause:
	cpi IGNORE_BUTTON, 1
	breq already_unpaused

	lds r16, PAUSING
	cpi r16, 0
	breq already_unpaused

	ldi IGNORE_BUTTON, 1

	ldi r16, 0
	sts PAUSING, r16

	ldi r16, 0x02
	sts TIMSK2, r16
	rjmp button_test_loop
	
	already_unpaused:
		ldi IGNORE_BUTTON, 1
		rjmp button_test_loop


TIMER2_SETUP:
	push r16	

	ldi r16, 0x02
	sts TCCR2A, r16

	; 1024 Prescaler
	ldi r16, 0x07
	sts TCCR2B, r16

	; Set OCR2A to the output compare value. This will be the last value that the
	; timer's counter actually holds
	ldi r16, 25
	sts OCR2A, r16
	
	; Starting with the timer off
	ldi r16, 0x00
	sts TIMSK2, r16

	ldi r16, 0x01
	sts TIFR2, r16
		
	pop r16
	ret
	
TIMER2_OVERFLOW_ISR:

	push r16
	lds r16, SREG ; Load the value of SREG into r16
	push r16 ; Push SREG onto the stack
	push YL
	push YH

	; Increment the value of OVERFLOW_INTERRUPT_COUNTER
	lds r16, OVERFLOW_INTERRUPT_COUNTER
	inc r16

	cp r16, SPEED ;;EDITED TIMER FROM 61 TO 15 - NEED TO CHANGE TO 1 TENTH OF SECOND, THAT IS 6
	brne timer2_isr_done

	; Setting an interrupt flag so that no other procedure is done while the interrupt
	; is being handled
	ldi INTERRUPT_FLAG, 1

	call ADD_TIME
	nop
	
LCD_DISPLAY:
	push r18
	; Set up the LCD to display starting on row 0, column 0
	ldi r18, 0 ; Row number
	push r18
	ldi r18, 0 ; Column number
	push r18
	call lcd_gotoxy

	pop r18
	pop r18
	pop r18

	push r18
	ldi r18, high(LINE_ONE)
	push r18
	ldi r18, low(LINE_ONE)
	push r18
	call lcd_puts

	pop r18
	pop r18
	pop r18

	clr r16 ; Set the counter back to 0

timer2_isr_done:
	; Store the overflow counter back to memory
	sts OVERFLOW_INTERRUPT_COUNTER, r16
	
	pop YH
	pop YL

	; The next stack value is the value of SREG
	pop r16 ; Pop SREG into r16
	sts SREG, r16 ; Store r16 into SREG
	; Now pop the original saved r16 value
	pop r16
	clr INTERRUPT_FLAG

	reti ; Return from interrupt	


; ADD_TIME: Updates the string in LINE_ONE to simulate the behaviour of a timer.
; Every time the last digit being compared reaches its limit, it "carries a one"
; on to the following significant value.
ADD_TIME:
	push r17
	push r18
	
	ldi r17, 1
	lds r18, (TIME+4)
	cpi r18, '9'
	breq restart_mil
	add r18, r17
	
	sts (TIME+4), r18
	st Y, r18
	pop r18
	pop r17
	ret

	restart_mil:
		lds r18, (TIME+3)
		cpi r18, '9'
		breq restart_sec1
		add r18, r17

		sbiw YL, 2

		sts (TIME+3), r18
		st Y, r18
		
		ldi r18, '0'
		adiw YL, 2

		sts (TIME+4), r18
		st Y, r18

		pop r18
		pop r17
		ret
	
	restart_sec1:
		lds r18, (TIME+2)
		cpi r18, '5'
		breq restart_sec2
		add r18, r17

		sbiw YL, 3
				
		sts (TIME+2), r18
		st Y, r18

		adiw YL, 1

		ldi r18, '0'
		sts (TIME+3), r18
		st Y, r18

		adiw YL, 2

		sts (TIME+4), r18
		st Y, r18
	
		pop r18
		pop r17
		ret
	
	restart_sec2:
		lds r18, (TIME+1)
		cpi r18, '9'
		breq restart_min
		add r18, r17

		sbiw YL, 5
		sts (TIME+1), r18
		st Y, r18

		adiw YL, 2
		ldi r18, '0'

		sts(TIME+2), r18
		st Y, r18

		adiw YL, 1

		sts (TIME+3), r18
		st Y, r18

		adiw YL, 2

		sts (TIME+4), r18
		st Y, r18

		pop r18
		pop r17
		ret
	
	restart_min:
		lds r18, TIME
		cpi r18, '9'
		breq restart_all
		add r18, r17
		
		sbiw YL, 6
		sts TIME, r18
		st Y, r18

		adiw YL, 1
		ldi r18, '0'

		sts (TIME+1), r18
		st Y, r18

		adiw YL, 2

		sts(TIME+2), r18
		st Y, r18

		adiw YL, 1

		sts (TIME+3), r18
		st Y, r18

		adiw YL, 2

		sts (TIME+4), r18
		st Y, r18

		pop r18
		pop r17
		ret
	
	restart_all:
		ldi r18, '0'

		sbiw YL, 6
		sts TIME, r18
		st Y, r18

		adiw YL, 1

		sts (TIME+1), r18
		st Y, r18

		adiw YL, 2

		sts(TIME+2), r18
		st Y, r18

		adiw YL, 1

		sts (TIME+3), r18
		st Y, r18

		adiw YL, 2

		sts (TIME+4), r18
		st Y, r18

		pop r18
		pop r17
		ret

; SET_LCD: Sets the LCD for LINE_ONE.
SET_LCD:
	; Set up the LCD to display starting on row 0, column 0
	push r18
	ldi r18, 0 ; Row number
	push r18
	ldi r18, 0 ; Column number
	push r18
	call lcd_gotoxy
	nop

	pop r18
	pop r18
	pop r18
	ret

; DISPLAY_STRING: Prints the string in LINE_ONE to the LCD screen.	
DISPLAY_STRING:
	; Display the string
	push r18
	ldi r18, high(LINE_ONE)
	push r18
	ldi r18, low(LINE_ONE)
	push r18
	call lcd_puts
	nop

	pop r18
	pop r18
	pop r18
	ret

; BUTTON HANDLING. The following six functions check for the pressing of buttons, and returns 
; a specific value depending on the button that was pressed.

right_pressed:
	ldi BUTTON_PRESSED, 1
	ret

up_pressed:
	lds	XL, ADCL
	lds	XH, ADCH
	
	ldi	r22, low(ADC_BTN_RIGHT)
	ldi	r23, high(ADC_BTN_RIGHT)
	
	cp	XL, r22
	cpc	XH, r23

	brsh set_up
	ret
	set_up:
		ldi BUTTON_PRESSED, 2

		ret
		
down_pressed:
	lds	XL, ADCL
	lds	XH, ADCH
	
	ldi	r22, low(ADC_BTN_UP)
	ldi	r23, high(ADC_BTN_UP)
	
	cp	XL, r22
	cpc	XH, r23

	brsh set_down
	ret
	set_down:
		ldi BUTTON_PRESSED, 3
		ret

left_pressed:
	lds	XL, ADCL
	lds	XH, ADCH
	
	ldi	r22, low(ADC_BTN_DOWN)
	ldi	r23, high(ADC_BTN_DOWN)
	
	cp	XL, r22
	cpc	XH, r23

	brsh set_left
	ret
	set_left:
		ldi BUTTON_PRESSED, 4

		ret

select_pressed:
	lds	XL, ADCL
	lds	XH, ADCH
	
	ldi	r22, low(ADC_BTN_LEFT)
	ldi	r23, high(ADC_BTN_LEFT)
	
	cp	XL, r22
	cpc	XH, r23

	brsh set_select
	ret
	set_select:
		ldi BUTTON_PRESSED, 5

		ret

none_pressed:
	lds	XL, ADCL
	lds	XH, ADCH
	
	ldi	r22, low(ADC_BTN_SELECT)
	ldi	r23, high(ADC_BTN_SELECT)
	
	cp	XL, r22
	cpc	XH, r23

	brsh set_none
	ret
	set_none:
		clr BUTTON_PRESSED

		ret

; SETTING_TIMER: Resets the TIME variable back to zero. In other words, this function initializes
; the TIME variable.
SETTING_TIMER:
	push r18
	push r16
	push YL
	push YH

	ldi r18, '0'

	sbiw YL, 6
	sts TIME, r18
	st Y, r18

	adiw YL, 1

	sts (TIME+1), r18
	st Y, r18

	adiw YL, 2

	sts (TIME+2), r18
	st Y, r18

	adiw YL, 1

	sts (TIME+3), r18
	st Y, r18

	adiw YL, 2

	sts (TIME+4), r18
	st Y, r18

	ldi r16, 0x00
	sts TIMSK2, r16

	ldi r16, 1
	sts PAUSING, r16

	pop YH
	pop YL
	pop r16
	pop r18
	ret

; INITIALIZE_LAPS: Resets or initializes the lap variables CURRENT_LAP and LAST_LAP.
INITIALIZE_LAPS:
	push r16

	ldi r16, '0'

	sts CURRENT_LAP, r16
	sts (CURRENT_LAP+1), r16

	ldi r16, ':'
	sts (CURRENT_LAP+2), r16

	ldi r16, '0'
	sts (CURRENT_LAP+3), r16
	sts (CURRENT_LAP+4), r16

	ldi r16, '.'
	sts (CURRENT_LAP+5), r16

	ldi r16, '0'
	sts (CURRENT_LAP+6), r16

	ldi r16, '0'
	sts LAST_LAP, r16
	sts (LAST_LAP+1), r16

	ldi r16, ':'
	sts (LAST_LAP+2), r16

	ldi r16, '0'
	sts (LAST_LAP+3), r16
	sts (LAST_LAP+4), r16

	ldi r16, '.'
	sts (LAST_LAP+5), r16

	ldi r16, '0'
	sts (LAST_LAP+6), r16

	pop r16
	ret

; STRCPY: Copies the time in LINE_ONE on to LINE_TWO, and updates the variables CURRENT_LAP
; and LAST_LAP. The time in LINE_ONE is copied on to CURRENT_LAP, and the time in CURRENT_LAP
; (before the copy) is copied on to LAST_LAP.
STRCPY:
	push YL
	push YH
	push XL
	push XH
	push r16

	ldi YL, low(LINE_ONE)
	ldi YH, high(LINE_ONE)
	adiw Y, 6

	; Load the address of LINE_TWO into Y
	ldi XL, low(LINE_TWO)
	ldi XH, high(LINE_TWO)
	; Call STRCPY_DM (which is in this file and does not use the stack for arguments)
	call STRCPY_HELPER
	nop

	; Position the cursor on row 1 (the second line), column 0
	
	ldi r16, 1 ; Row number
	push r16
	ldi r16, 0 ; Column number
	push r16
	call lcd_gotoxy
	nop

	pop r16
	pop r16
	
	; Display the string
	ldi r16, high(LINE_TWO)
	push r16
	ldi r16, low(LINE_TWO)
	push r16
	call lcd_puts
	nop

	pop r16
	pop r16

	pop r16
	pop XH
	pop XL
	pop YH
	pop YL

	ret

; STRCPY_HELPER: Does the copying routine for CURRENT_LAP and LAST_LAP variables from string Y. This
; function also prepares the output string X.
STRCPY_HELPER:
	push XL
	push XH
	push YL
	push YH
	push r16 ; Scratch register

	lap_cpy:
		lds r16, CURRENT_LAP
		sts LAST_LAP, r16

		ld r16, Y+
		sts CURRENT_LAP, r16

		lds r16, (CURRENT_LAP+1)
		sts (LAST_LAP+1), r16

		ld r16, Y+
		sts (CURRENT_LAP+1), r16

		lds r16, (CURRENT_LAP+2)
		sts (LAST_LAP+2), r16

		ld r16, Y+
		sts (CURRENT_LAP+2), r16

		lds r16, (CURRENT_LAP+3)
		sts (LAST_LAP+3), r16

		ld r16, Y+
		sts (CURRENT_LAP+3), r16

		lds r16, (CURRENT_LAP+4)
		sts (LAST_LAP+4), r16

		ld r16, Y+
		sts (CURRENT_LAP+4), r16

		lds r16, (CURRENT_LAP+5)
		sts (LAST_LAP+5), r16

		ld r16, Y+
		sts (CURRENT_LAP+5), r16

		lds r16, (CURRENT_LAP+6)
		sts (LAST_LAP+6), r16

		ld r16, Y+
		sts (CURRENT_LAP+6), r16

	output_string:
		lds r16, LAST_LAP
		st X+, r16

		lds r16, (LAST_LAP+1)
		st X+, r16

		lds r16, (LAST_LAP+2)
		st X+, r16

		lds r16, (LAST_LAP+3)
		st X+, r16

		lds r16, (LAST_LAP+4)
		st X+, r16

		lds r16, (LAST_LAP+5)
		st X+, r16

		lds r16, (LAST_LAP+6)
		st X+, r16

		ldi r16, ' '
		st X+, r16
		st X+, r16

		lds r16, CURRENT_LAP
		st X+, r16

		lds r16, (CURRENT_LAP+1)
		st X+, r16

		lds r16, (CURRENT_LAP+2)
		st X+, r16

		lds r16, (CURRENT_LAP+3)
		st X+, r16

		lds r16, (CURRENT_LAP+4)
		st X+, r16

		lds r16, (CURRENT_LAP+5)
		st X+, r16

		lds r16, (CURRENT_LAP+6)
		st X+, r16

		ldi r16, 0
		st X+, r16
		st X, r16

	pop r16
	pop YH
	pop YL
	pop XH
	pop XL
	ret

; CLEAR_LAPS: Sets both laps back to '0' (or reinitializes them)
CLEAR_LAPS:
	push XL
	push XH
	push r16
	push r19
	
	call INITIALIZE_LAPS
	nop

	ldi XL, low(LINE_TWO)
	ldi XH, high(LINE_TWO)
	ldi r16, ' '

	push XL
	push XH

	strcpy_dm_loop:
		; Get the next character from the input array (and increment the pointer)
		; Store it into the output array (and increment the pointer)
		
		st X+, r16
		
		ld r19, X

	
		; If the character is not a null terminator, the string continues, so continue
		; the loop.
		cpi r19, 0
		brne strcpy_dm_loop
	
	pop XH
	pop XL

	ldi r16, 1 ; Row number
	push r16
	ldi r16, 0 ; Column number
	push r16
	call lcd_gotoxy
	pop r16
	pop r16

	ldi r16, high(LINE_TWO)
	push r16
	ldi r16, low(LINE_TWO)
	push r16
	call lcd_puts
	pop r16
	pop r16
	
	pop r19
	pop r16
	pop XH
	pop XL
	ret

; DELAY_FUNCTION: Mitigates button aliasing
DELAY_FUNCTION:
	; We need to use r0, r16 and r20-23 (D0-D3)
	; Since these registers might contain data that the caller
	; wants to preserve, we will save their current values to memory
	; and load them when the function ends.
	; We use the push instruction to push each value onto the stack
	; and then pop them at the end of the function. Remember to pop
	; values in reverse order from the push ordering.
	push r0
	push r16
	push D0
	push D1
	push D2
	push D3
	
	
	; This "function" assumes that the return address (to jump
	; to when the function ends) has been stored in R31:R30 = Z
	; Load the counter_value into D3:D0
	ldi	D0, CV0
	ldi D1, CV1
	ldi D2, CV2
	ldi D3, CV3
delay_loop:
	; Subtract 1 from the counter
	ldi r16, 1
	clr r0
	sub D0, r16
	sbc D1, r0
	sbc D2, r0
	sbc D3, r0
	; If the C flag is not set, the value D3:D0
	; hasn't wrapped around yet.
	brcc delay_loop
	
	; Reload the saved values of registers r0, r16, r20-r23
	pop D3
	pop D2
	pop D1
	pop D0
	pop r16
	pop r0
	
	; Now, use the RET instruction to return
	; RET pops the stack twice to obtain the 16-bit
	; return address, then jumps to that address.
	ret
	
; Include LCD library code
.include "lcd_function_code.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                               Data Section                                  ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.dseg
; Note that no .org 0x200 statement should be present
; Put variables and data arrays here...
	
LINE_ONE: .byte 50
LINE_TWO: .byte 50
CURRENT_LAP: .byte 7
LAST_LAP: .byte 7
TIME:  .byte 5
OVERFLOW_INTERRUPT_COUNTER: .byte 1
PAUSING: .byte 1 

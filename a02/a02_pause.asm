; a02_pause.asm
; Name: Jorge Fernando Flores Pinto
; ID: V00880059
; CSC230
; Summer 2017

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                        Constants and Definitions                            ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Special register definitions

.def IGNORE_BUTTON = r17
.def CURRENT_LED = r20
.def DIRECTION = r21
.def SPEED = r24
.def BUTTON_PRESSED = r25

.def XL = r26
.def XH = r27

.def INVERTED = r28
.def SWAPPER = r29
.def SEL_FLAG = r30
.def COUNTER = r31

.equ SP01 = 244
.equ SP02 = 122
.equ SP03 = 61
.equ SP04 = 30
.equ SP05 = 15
.equ SP06 = 7

; Stack pointer and SREG registers (in data space)
.equ SPH = 0x5E
.equ SPL = 0x5D
.equ SREG = 0x5F

; Initial address (16-bit) for the stack pointer
.equ STACK_INIT = 0x21FF

; Port and data direction register definitions (taken from AVR Studio; note that m2560def.inc does not give the data space address of PORTB)
.equ DDRB = 0x24
.equ PORTB = 0x25
.equ DDRL = 0x10A
.equ PORTL = 0x10B

; Definitions for the analog/digital converter (ADC)
.equ ADCSRA	= 0x7A ; Control and Status Register A
.equ ADCSRB	= 0x7B ; Control and Status Register B
.equ ADMUX	= 0x7C ; Multiplexer Register
.equ ADCL	= 0x78 ; Output register (high bits)
.equ ADCH	= 0x79 ; Output register (low bits)

; Definitions for button values from the ADC
; Comment out one set of values.
; Option A (v 1.1)
;.equ ADC_BTN_RIGHT = 0x032
;.equ ADC_BTN_UP = 0x0FA
;.equ ADC_BTN_DOWN = 0x1C2
;.equ ADC_BTN_LEFT = 0x28A
;.equ ADC_BTN_SELECT = 0x352

; Option B (v 1.0)
.equ ADC_BTN_RIGHT	= 0x032
.equ ADC_BTN_UP		= 0x0C3
.equ ADC_BTN_DOWN	= 0x17C
.equ ADC_BTN_LEFT	= 0x22B
.equ ADC_BTN_SELECT	= 0x316

; Definitions of the special register addresses for timer 2 (in data space)
.equ ASSR = 0xB6
.equ OCR2A = 0xB3
.equ OCR2B = 0xB4
.equ TCCR2A = 0xB0
.equ TCCR2B = 0xB1
.equ TCNT2  = 0xB2
.equ TIFR2  = 0x37
.equ TIMSK2 = 0x70


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

.org 0x0074

	; From the pinout diagram: 
	; Pin 42 - Port L, bit 7
	; Pin 44 - Port L, bit 5
	; Pin 46 - Port L, bit 3
	; Pin 48 - Port L, bit 1
	; Pin 50 - Port B, bit 3
	; Pin 52 - Port B, bit 1

main_begin:
	ldi SPEED, 244
	ldi CURRENT_LED, 0x01
	ldi DIRECTION, 0x01
	ldi INVERTED, 0x00
	clr SEL_FLAG
	clr IGNORE_BUTTON

	; Set up the data direction register for PORTB and PORTL for output
	ldi	r16, 0xff
	sts	DDRB, r16
	sts	DDRL, r16

	ldi r16, high(STACK_INIT)
	sts SPH, r16
	ldi r16, low(STACK_INIT)
	sts SPL, r16

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

	ldi r16, 0x00
	sts PORTL, r16
	ldi	r16, 0x02
	sts PORTB, r16

	ldi	r22, low(ADC_BTN_SELECT)
	ldi	r23, high(ADC_BTN_SELECT)

	ldi r16, 0
	sts OVERFLOW_INTERRUPT_COUNTER, r16
	
	call TIMER2_SETUP ; Set up timer 0 control registers (function below)
	
	sei ; Set the I flag in SREG to enable interrupt processing

button_test_loop:
	; Start an ADC conversion
	
	; Set the ADSC bit to 1 in the ADCSRA register to start a conversion
	lds	r16, ADCSRA
	ori	r16, 0x40
	sts	ADCSRA, r16

regular_mode:
	lds	r16, ADCSRA
	andi r16, 0x40
	brne regular_mode

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

	cpi BUTTON_PRESSED, 1
	breq swapping_normal

	cpi BUTTON_PRESSED, 2
	breq speed_up

	cpi BUTTON_PRESSED, 3
	breq normal_speed

	cpi BUTTON_PRESSED, 4
	breq swapping_inverted

	cpi BUTTON_PRESSED, 5
	breq pause

	rjmp button_test_loop

skip:

	clr IGNORE_BUTTON
	rjmp button_test_loop


swapping_normal:
	
	cpi IGNORE_BUTTON, 1
	breq already_normal

	cpi INVERTED, 0x00
	breq already_normal

	ldi INVERTED, 0x00

	lds r16, PORTB
	ldi SWAPPER, 0x0A
	eor r16, SWAPPER
	sts PORTB, r16

	lds r16, PORTL
	ldi SWAPPER, 0xAA
	eor r16, SWAPPER
	sts PORTL, r16


	already_normal:
		ldi IGNORE_BUTTON, 1
		rjmp button_test_loop


swapping_inverted:

	cpi IGNORE_BUTTON, 1
	breq already_inverted

	cpi INVERTED, 0x01
	breq already_inverted

	ldi INVERTED, 0x01

	lds r16, PORTB
	ldi SWAPPER, 0x0A
	eor r16, SWAPPER
	sts PORTB, r16

	lds r16, PORTL
	ldi SWAPPER, 0xAA
	eor r16, SWAPPER
	sts PORTL, r16

	already_inverted:
		ldi IGNORE_BUTTON, 1
		rjmp button_test_loop

speed_up:
	
	cpi IGNORE_BUTTON, 1
	breq already_fast
	ldi SPEED, 61
	ldi IGNORE_BUTTON, 1
	rjmp button_test_loop

	already_fast:
		rjmp button_test_loop


normal_speed:

	cpi IGNORE_BUTTON, 1
	breq already_normal_speed
	ldi SPEED, 244
	ldi IGNORE_BUTTON, 1 
	rjmp button_test_loop

	already_normal_speed:
		rjmp button_test_loop
	
pause:

	cpi IGNORE_BUTTON, 1
	breq already_paused

	cpi SEL_FLAG, 1
	breq unpause
	ldi SEL_FLAG, 1
	ldi IGNORE_BUTTON, 1 
	rjmp button_test_loop

	already_paused:
		rjmp button_test_loop

unpause:

	cpi IGNORE_BUTTON, 1
	breq already_unpaused

	clr SEL_FLAG
	ldi IGNORE_BUTTON, 1 
	rjmp button_test_loop

	already_unpaused:
		rjmp button_test_loop



; Timer setup

TIMER2_SETUP:
	push r16	

	ldi r16, 0x01
	sts TIMSK2, r16

	ldi r16, 0x06
	sts TCCR2B, r16

	ldi r16, 0x01
	sts TIFR2, r16
		
	pop r16
	ret


TIMER2_OVERFLOW_ISR:

	push r16
	lds r16, SREG ; Load the value of SREG into r16
	push r16 ; Push SREG onto the stack
	push r17
	push r18

	; Increment the value of OVERFLOW_INTERRUPT_COUNTER
	lds r16, OVERFLOW_INTERRUPT_COUNTER
	inc r16
	
	cpi SEL_FLAG, 1
	breq timer2_isr_done

	cp r16, SPEED
	brne timer2_isr_done

	; If 244 interrupts have occurred, flip the value of LED 52
	call convert

	
	clr r16 ; Set the counter back to 0
	
	cpi DIRECTION, 0x01
	breq positive
	brne negative

	positive:
		inc CURRENT_LED
		rjmp timer2_isr_done
	negative:
		dec CURRENT_LED
		rjmp timer2_isr_done
	
timer2_isr_done:
	; Store the overflow counter back to memory
	sts OVERFLOW_INTERRUPT_COUNTER, r16
	
	pop r18
	pop r17
	; The next stack value is the value of SREG
	pop r16 ; Pop SREG into r16
	sts SREG, r16 ; Store r16 into SREG
	; Now pop the original saved r16 value
	pop r16

	reti ; Return from interrupt

convert:

	cpi CURRENT_LED, 0x00
	breq light_52
	
	cpi CURRENT_LED, 0x01
	breq light_50
	
	cpi CURRENT_LED, 0x02
	breq light_48

	cpi CURRENT_LED, 0x03
	breq light_46

	cpi CURRENT_LED, 0x04
	breq light_44

	cpi CURRENT_LED, 0x05
	breq light_42

	light_52:
		ldi DIRECTION, 0x01
		ldi r16, 0x00
		sts PORTL, r16
		ldi	r16, 0x02
		sts PORTB, r16
		
		rjmp return

	light_50:
		ldi r16, 0x00
		sts PORTL, r16
		ldi	r16, 0x08
		sts PORTB, r16
		rjmp return

	light_48:
		ldi r16, 0x00
		sts PORTB, r16
		ldi r16, 0x02
		sts PORTL, r16
		rjmp return

	light_46:
		ldi r16, 0x08
		sts PORTL, r16
		rjmp return

	light_44:
		ldi r16, 0x20
		sts PORTL, r16
		rjmp return

	light_42:
		neg DIRECTION
		ldi r16, 0x80
		sts PORTL, r16
		rjmp return

	return:
		cpi INVERTED, 0x01
		breq invert
		ret
	
	invert:
		cpi CURRENT_LED, 0x03
		brsh invert2
		
		lds r16, PORTB
		ldi r18, 0x0A
		eor r16, r18
		sts PORTB, r16

		invert2:
			lds r16, PORTL
			ldi r18, 0xAA
			eor r16, r18
			sts PORTL, r16
		
		ret
		
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


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                               Data Section                                  ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.dseg
.org 0x200

OVERFLOW_INTERRUPT_COUNTER: .byte 1

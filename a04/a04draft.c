/* a04.c (well, a04draft.c technically...)
   Name: Jorge Fernando Flores Pinto
   ID: V00880059
   CSC230, Summer 2017

   a04.c is a timer with lap functionalities.
   I used and modified some of Bill's code and worked from it.
   I have kept some of his comments as well.
*/

#define  ADC_BTN_RIGHT 0x032
#define  ADC_BTN_UP 0x0C3
#define  ADC_BTN_DOWN 0x17C
#define  ADC_BTN_LEFT 0x22B
#define  ADC_BTN_SELECT 0x316

#include "CSC230.h"
#include <stdio.h>
#include <string.h>

//This global variable is used to count the number of interrupts
//which have occurred. Note that 'int' is a 16-bit type in this case.
int interrupt_count = 0;
int ignore_button_flag = 0;
int button_pressed = 0;
int pause_flag = 1;

char current_time[8];
char current_lap_time[8];
char previous_lap_time[8];
int iterations = 0;

//Define the ISR for the timer 2 overflow interrupt.
//A short is 16 bits wide, so the entire ADC result can be stored
//in an unsigned short.
unsigned short poll_adc(){
	unsigned short adc_result = 0; //16 bits
	
	ADCSRA |= 0x40;
	while((ADCSRA & 0x40) == 0x40); //Busy-wait
	
	unsigned short result_low = ADCL;
	unsigned short result_high = ADCH;
	
	adc_result = (result_high<<8)|result_low;
	return adc_result;
}
//update_time(char *time)
//
//Takes a time paramater and increases one tenth of a second.
char *update_time(char *time) {
	if (time[6] != '9') {
		time[6]++;
	}
	else {
		time[6] = '0';
		if(time[4] != '9') {
			time[4]++;
		}
		else {
			time[4] = '0';
			if(time[3] != '5') {
				time[3]++;
			}
			else {
				time[3] = '0';
				if (time[1] != '9') {
					time[1]++;
				}
				else {
					time[1] = '0';
					if (time[0] != '9') {
						time[0]++;
					}
					else {
						time[0] = '0';
					}
				}
			}
		}
	}
	return time;
}
//char *reset_time(char *time)
//
//Sets time back to initial value.
void reset_time(char *time){
	char *init = "00:00.0";
	char initial_time[8];
	strncpy(initial_time, init, 7);

	strncpy(time, initial_time, 7);


}
//Initializes time and lap times.
void initialize_strings() {
	char *init = "00:00.0";
	strncpy(current_time, init, 7);
	strncpy(current_lap_time, init, 7);
	strncpy(previous_lap_time, init, 7);

}
//Updates the values of the laps.
void set_laps() {
	strncpy(previous_lap_time, current_lap_time, 7);
	strncpy(current_lap_time, current_time, 7);

}

ISR(TIMER2_COMPA_vect){

	interrupt_count++;
	if(iterations >= 100) {
		iterations = 0;
		interrupt_count = 0;
		_delay_ms(20);
	}

	if (interrupt_count >= 60){
		iterations++;
		interrupt_count -= 60;
		update_time(current_time);
		lcd_xy(6,0);
		lcd_puts(current_time);
		

	}
}

// timer2_setup()
// Set the control registers for timer 2 to enable
// the output compare interrupt and set a prescaler of 1024.
void timer2_setup() {

	TIMSK2 = 0x00;

	TCCR2A = 0x02;
	OCR2A = 0x19;
	OCR2B = 0x01;
	TCNT2 = 0x00;
	TIFR2 = 0x01;
	TCCR2B = 0x07; //Prescaler of 1024

}
//Checks the button that was pressed
int button_routine() {
	short adc_result = poll_adc();
	
	if (adc_result < ADC_BTN_RIGHT){
		button_pressed = 1; // rigth pressed
	}
	else if (adc_result >= ADC_BTN_RIGHT && adc_result < ADC_BTN_UP){
		button_pressed = 2; //up pressed
	}
	else if (adc_result >= ADC_BTN_UP && adc_result < ADC_BTN_DOWN){
		button_pressed = 3; // down pressed
	}
	else if (adc_result >= ADC_BTN_DOWN && adc_result < ADC_BTN_LEFT){
		button_pressed = 4; //left pressed
	}
	else if (adc_result >= ADC_BTN_LEFT && adc_result < ADC_BTN_SELECT){
		button_pressed = 5; //select pressed
	}
	else {
		button_pressed = 0; //none pressed
	}
	return 1;

}

int main(){
	ADCSRA = 0x87;
	ADMUX = 0x40;

	timer2_setup();
	
	//Call LCD init (should only be called once)
	lcd_init();
	sei(); 

	initialize_strings();

	lcd_xy(0,0);
	lcd_puts("Time: ");
	lcd_puts(current_time);

	while(1) {
		button_routine();
		
		_delay_ms(50);		

		if (button_pressed == 0) {
			ignore_button_flag = 0;
			continue;
		}
		if (ignore_button_flag == 1) {
			continue;
		}
		
		if (button_pressed == 1 && ignore_button_flag != 1) {
			ignore_button_flag = 1;
			continue;	
		}

		//IMPLEMENT UP
		else if (button_pressed == 2 && ignore_button_flag != 1) {
			ignore_button_flag = 1;
			set_laps();
			lcd_xy(0,1);
			lcd_puts(previous_lap_time);
			lcd_xy(9,1);
			lcd_puts(current_lap_time);
		}

		//IMPLEMENT DOWN
		else if (button_pressed == 3 && ignore_button_flag != 1) {
			ignore_button_flag = 1;
			lcd_xy(0,1);
			lcd_puts("                ");
			reset_time(previous_lap_time);
			reset_time(current_lap_time);
		}

		//IMPLEMENT LEFT
		else if (button_pressed == 4 && ignore_button_flag != 1) {
			ignore_button_flag = 1;
			TIMSK2 = 0x00;
			pause_flag = 1;
			reset_time(current_time);
			reset_time(current_lap_time);
			lcd_xy(6,0);
			lcd_puts(current_time);

		}

		//IMPLEMENT SELECT
		else if (button_pressed == 5 && ignore_button_flag != 1) {
			ignore_button_flag = 1;
			if (pause_flag == 0) { //pause
				TIMSK2 = 0x00;
				pause_flag = 1;
			}
			else { //unpause
				TIMSK2 = 0x02;
				pause_flag = 0;
			}
			
		}
	
	}

	return 0;
	
}

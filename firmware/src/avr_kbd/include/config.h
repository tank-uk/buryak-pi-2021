#ifndef config_h
#define config_h

// Joystick type
#define JOY_KEMPSTON 0
#define JOY_SEGA 1

#ifndef JOY_TYPE
#define JOY_TYPE JOY_SEGA // JOY_SEGA
#endif

// Pins
#define PIN_BTN_NMI 0
#define PIN_KBD_DAT 1
#define PIN_KBD_CLK 2 
#define PIN_SS 10 // SPI slave select

#define LED_PWR A0
#define LED_KBD A1
#define LED_TURBO A2
#define LED_ROMBANK A3
#define LED_PAUSE A4
#define AUDIO_OFF A5

#define JOY_UP 5    
#define JOY_DOWN 6  
#define JOY_LEFT 7  
#define JOY_RIGHT 8 
#define JOY_FIRE 9 
#define JOY_FIRE2 3
#define JOY_FIRE3 4

// EEPROM offsets
#define EEPROM_TURBO_ADDRESS 0x00
#define EEPROM_ROMBANK_ADDRESS 0x01

// EEPROM values
#define EEPROM_VALUE_TRUE 10
#define EEPROM_VALUE_FALSE 20

#define CMD_INIT 0xF0
#define CMD_NONE 0xFF

#endif
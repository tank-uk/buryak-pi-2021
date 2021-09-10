/*
 * AVR keyboard firmware for Buryak-Pi 2021 project
 * 
 * Designed to build on PlatformIO env.
 * 
 * External libraries: https://github.com/jonthysell/SegaController/, https://github.com/techpaul/PS2KeyRaw
 * Arduino libraries: SPI, EEPROM
 * 
 * @author Andy Karpov <andy.karpov@gmail.com>
 * Ukraine, 2021
 */

#include "config.h"
#include "PS2KeyRaw.h"
#include "matrix.h"
#include "ps2_codes.h"
#include <EEPROM.h>
#include <SPI.h>

PS2KeyRaw kbd;

#if JOY_TYPE==JOY_SEGA
  #include "SegaController.h" // https://github.com/jonthysell/SegaController/
  SegaController joystick(JOY_FIRE3, JOY_UP, JOY_DOWN, JOY_LEFT, JOY_RIGHT, JOY_FIRE, JOY_FIRE2); // db9_pin_7, db9_pin_1, db9_pin_2, db9_pin_3, db9_pin_4, db9_pin_6, db9_pin_9
  word joy_current_state = 0;
  word joy_last_state = 0;
#endif

SPISettings settingsA(8000000, MSBFIRST, SPI_MODE0); // SPI transmission settings

bool matrix[ZX_MATRIX_FULL_SIZE]; // matrix of pressed keys + special keys to be transmitted on CPLD side by SPI protocol

byte turbo = 0x0;
bool is_turbo = false;
bool is_wait = false;
byte rom_bank = 0x0;
bool blink = false;
bool init_done = false;

unsigned long t = 0;  // current time
unsigned long tl = 0; // led poll time
unsigned long te = 0; // eeprom store time
unsigned long tb = 0; // blink state

int capsed_keys[20] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int capsed_keys_size = 0;

void push_capsed_key(int key);
void pop_capsed_key(int key);
void process_capsed_key(int key, bool up);
void fill_kbd_matrix(int sc);
uint8_t get_matrix_byte(uint8_t pos);
void spi_send(uint8_t addr, uint8_t data);
void transmit_keyboard_matrix();
void send_macros(uint8_t pos);
void do_reset();
void do_magick();
void set_rombank(byte bank);
void clear_matrix(int clear_size);
bool eeprom_restore_bool(int addr, bool default_value);
byte eeprom_restore_byte(int addr, byte default_value);
void eeprom_store_bool(int addr, bool value);
void eeprom_store_byte(int addr, byte value);
void eeprom_restore_values();
void eeprom_store_values();
void setup();
void loop();

void push_capsed_key(int key)
{
  int i = 0;
  bool found = false;
  if (capsed_keys_size > 0) {
    for (i=0; i<capsed_keys_size; i++) {
      if (capsed_keys[i] == key) {
        found = true;
      }
    }
  }
  if (!found && capsed_keys_size < 20) {
    capsed_keys[capsed_keys_size] = key;
    capsed_keys_size++;
  }
}

void pop_capsed_key(int key)
{
  int i = 0;
  int j = 0;
  int tmp_array[20] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
  if (capsed_keys_size > 0) {
    for (i=0; i<capsed_keys_size; i++) {
      if (capsed_keys[i] != key) {
        tmp_array[j] = capsed_keys[i];
        j++;
      }
    }
  }
  if (j > 0) {
    for (i=0; i<j; i++) {
      capsed_keys[i] = tmp_array[i];
    }
  }
  capsed_keys_size = j;
}

void process_capsed_key(int key, bool up)
{
  if (!up) {
    push_capsed_key(key);
  } else {
    pop_capsed_key(key);
  }
}

// transform PS/2 scancodes into internal matrix of pressed keys
void fill_kbd_matrix(int sc)
{

  static bool is_up=false, is_e=false, is_e1=false;
  static bool is_ctrl=false, is_alt=false, is_del=false, is_bksp=false, is_shift=false, is_ss_used=false;

  // is extended scancode prefix
  if (sc == 0xE0) {
    is_e = 1;
    return;
  }

 if (sc == 0xE1) {
    is_e = 1;
    is_e1 = 1;
    return;
  }

  // is key released prefix
  if (sc == 0xF0 && !is_up) {
    is_up = 1;
    return;
  }

  int scancode = sc + ((is_e || is_e1) ? 0x100 : 0);

  is_ss_used = false;

  switch (scancode) {
  
    // Shift -> CS for ZX
    case PS2_L_SHIFT: 
    case PS2_R_SHIFT:
      matrix[ZX_K_CS] = !is_up;
      is_shift = !is_up;
      break;

    // Ctrl -> SS for ZX
    case PS2_L_CTRL:
    case PS2_R_CTRL:
      matrix[ZX_K_SS] = !is_up;
      is_ctrl = !is_up;
      break;

    // Alt (L) -> SS+CS for ZX
    case PS2_L_ALT:
      matrix[ZX_K_SS] = !is_up;
      matrix[ZX_K_CS] = !is_up;
      is_alt = !is_up;
      process_capsed_key(scancode, is_up);
      break;

    // Alt (R) -> SS+CS for ZX
    case PS2_R_ALT:
      matrix[ZX_K_SS] = !is_up;
      matrix[ZX_K_CS] = !is_up;
      is_alt = !is_up;
      process_capsed_key(scancode, is_up);
      break;

    // Del -> SS+C for ZX
    case PS2_DELETE:
       matrix[ZX_K_SS] = !is_up;
       matrix[ZX_K_C] =  !is_up;
      is_del = !is_up;
    break;

    // Ins -> SS+A for ZX
    case PS2_INSERT:
       matrix[ZX_K_SS] = !is_up;
       matrix[ZX_K_A] =  !is_up;
    break;

    // Cursor -> CS + 5,6,7,8
    case PS2_UP:
      matrix[ZX_K_CS] = !is_up;
      matrix[ZX_K_7] = !is_up;
      process_capsed_key(scancode, is_up);
      break;
    case PS2_DOWN:
      matrix[ZX_K_CS] = !is_up;
      matrix[ZX_K_6] = !is_up;
      process_capsed_key(scancode, is_up);
      break;
    case PS2_LEFT:
      matrix[ZX_K_CS] = !is_up;
      matrix[ZX_K_5] = !is_up;
      process_capsed_key(scancode, is_up);
      break;
    case PS2_RIGHT:
      matrix[ZX_K_CS] = !is_up;
      matrix[ZX_K_8] = !is_up;
      process_capsed_key(scancode, is_up);
      break;

    // ESC -> CS+SPACE for ZX
    case PS2_ESC:
      matrix[ZX_K_CS] = !is_up;
      matrix[ZX_K_SP] = !is_up;
      process_capsed_key(scancode, is_up);
      break;

    // Backspace -> CS+0
    case PS2_BACKSPACE:
      matrix[ZX_K_CS] = !is_up;
      matrix[ZX_K_0] = !is_up;
      process_capsed_key(scancode, is_up);
      is_bksp = !is_up;
      break;

    // Enter
    case PS2_ENTER:
    case PS2_KP_ENTER:
      matrix[ZX_K_ENT] = !is_up;
      break;

    // Space
    case PS2_SPACE:
      matrix[ZX_K_SP] = !is_up;
      break;

    // Letters & numbers
    case PS2_A: matrix[ZX_K_A] = !is_up; break;
    case PS2_B: matrix[ZX_K_B] = !is_up; break;
    case PS2_C: matrix[ZX_K_C] = !is_up; break;
    case PS2_D: matrix[ZX_K_D] = !is_up; break;
    case PS2_E: matrix[ZX_K_E] = !is_up; break;
    case PS2_F: matrix[ZX_K_F] = !is_up; break;
    case PS2_G: matrix[ZX_K_G] = !is_up; break;
    case PS2_H: matrix[ZX_K_H] = !is_up; break;
    case PS2_I: matrix[ZX_K_I] = !is_up; break;
    case PS2_J: matrix[ZX_K_J] = !is_up; break;
    case PS2_K: matrix[ZX_K_K] = !is_up; break;
    case PS2_L: matrix[ZX_K_L] = !is_up; break;
    case PS2_M: matrix[ZX_K_M] = !is_up; break;
    case PS2_N: matrix[ZX_K_N] = !is_up; break;
    case PS2_O: matrix[ZX_K_O] = !is_up; break;
    case PS2_P: matrix[ZX_K_P] = !is_up; break;
    case PS2_Q: matrix[ZX_K_Q] = !is_up; break;
    case PS2_R: matrix[ZX_K_R] = !is_up; break;
    case PS2_S: matrix[ZX_K_S] = !is_up; break;
    case PS2_T: matrix[ZX_K_T] = !is_up; break;
    case PS2_U: matrix[ZX_K_U] = !is_up; break;
    case PS2_V: matrix[ZX_K_V] = !is_up; break;
    case PS2_W: matrix[ZX_K_W] = !is_up; break;
    case PS2_X: matrix[ZX_K_X] = !is_up; break;
    case PS2_Y: matrix[ZX_K_Y] = !is_up; break;
    case PS2_Z: matrix[ZX_K_Z] = !is_up; break;

    // digits
    case PS2_0: matrix[ZX_K_0] = !is_up; break;
    case PS2_1: matrix[ZX_K_1] = !is_up; break;
    case PS2_2: matrix[ZX_K_2] = !is_up; break;
    case PS2_3: matrix[ZX_K_3] = !is_up; break;
    case PS2_4: matrix[ZX_K_4] = !is_up; break;
    case PS2_5: matrix[ZX_K_5] = !is_up; break;
    case PS2_6: matrix[ZX_K_6] = !is_up; break;
    case PS2_7: matrix[ZX_K_7] = !is_up; break;
    case PS2_8: matrix[ZX_K_8] = !is_up; break;
    case PS2_9: matrix[ZX_K_9] = !is_up; break;

    // Keypad digits
    case PS2_KP_0: matrix[ZX_K_0] = !is_up; break;
    case PS2_KP_1: matrix[ZX_K_1] = !is_up; break;
    case PS2_KP_2: matrix[ZX_K_2] = !is_up; break;
    case PS2_KP_3: matrix[ZX_K_3] = !is_up; break;
    case PS2_KP_4: matrix[ZX_K_4] = !is_up; break;
    case PS2_KP_5: matrix[ZX_K_5] = !is_up; break;
    case PS2_KP_6: matrix[ZX_K_6] = !is_up; break;
    case PS2_KP_7: matrix[ZX_K_7] = !is_up; break;
    case PS2_KP_8: matrix[ZX_K_8] = !is_up; break;
    case PS2_KP_9: matrix[ZX_K_9] = !is_up; break;

    // '/" -> SS+P / SS+7
    case PS2_QUOTE:
      matrix[ZX_K_SS] = !is_up;
      matrix[is_shift ? ZX_K_P : ZX_K_7] = !is_up;
      if (is_up) {
        matrix[ZX_K_P] = false;
        matrix[ZX_K_7] = false;
      }
      is_ss_used = is_shift;
      break;

    // ,/< -> SS+N / SS+R
    case PS2_COMMA:
      matrix[ZX_K_SS] = !is_up;
      matrix[is_shift ? ZX_K_R : ZX_K_N] = !is_up;
      if (is_up) {
        matrix[ZX_K_R] = false;
        matrix[ZX_K_N] = false;
      }
      is_ss_used = is_shift;
      break;

    // ./> -> SS+M / SS+T
    case PS2_PERIOD:
    case PS2_KP_PERIOD:
      matrix[ZX_K_SS] = !is_up;
      matrix[is_shift ? ZX_K_T : ZX_K_M] = !is_up;
      if (is_up) {
        matrix[ZX_K_T] = false;
        matrix[ZX_K_M] = false;
      }
      is_ss_used = is_shift;
      break;

    // ;/: -> SS+O / SS+Z
    case PS2_SEMICOLON:
      matrix[ZX_K_SS] = !is_up;
      matrix[is_shift ? ZX_K_Z : ZX_K_O] = !is_up;
      if (is_up) {
        matrix[ZX_K_Z] = false;
        matrix[ZX_K_O] = false;
      }
      is_ss_used = is_shift;
      break;

    // [,{ -> SS+Y / SS+F
    case PS2_L_BRACKET:
      if (!is_up) {
        send_macros(is_shift ? ZX_K_F : ZX_K_Y);
      }
      break;

    // ],} -> SS+U / SS+G
    case PS2_R_BRACKET:
      if (!is_up) {
        send_macros(is_shift ? ZX_K_G : ZX_K_U);
      }
      break;

    // /,? -> SS+V / SS+C
    case PS2_SLASH:
    case PS2_KP_SLASH:
      matrix[ZX_K_SS] = !is_up;
      matrix[is_shift ? ZX_K_C : ZX_K_V] = !is_up;
      if (is_up) {
        matrix[ZX_K_C] = false;
        matrix[ZX_K_V] = false;
      }
      is_ss_used = is_shift;
      break;

    // \,| -> SS+D / SS+S
    case PS2_BACK_SLASH:
      if (!is_up) {
        send_macros(is_shift ? ZX_K_S : ZX_K_D);
      }
      break;

    // =,+ -> SS+L / SS+K
    case PS2_EQUALS:
      matrix[ZX_K_SS] = !is_up;
      matrix[is_shift ? ZX_K_K : ZX_K_L] = !is_up;
      if (is_up) {
        matrix[ZX_K_K] = false;
        matrix[ZX_K_L] = false;
      }
      is_ss_used = is_shift;
      break;

    // -,_ -> SS+J / SS+0
    case PS2_MINUS:
      matrix[ZX_K_SS] = !is_up;
      matrix[is_shift ? ZX_K_0 : ZX_K_J] = !is_up;
      if (is_up) {
        matrix[ZX_K_0] = false;
        matrix[ZX_K_J] = false;
      }
      is_ss_used = is_shift;
      break;

    // `,~ -> SS+X / SS+A
    case PS2_ACCENT:
      if (is_shift and !is_up) {
        send_macros(is_shift ? ZX_K_A : ZX_K_X);
      }
      if (!is_shift) {
        matrix[ZX_K_SS] = !is_up;
        matrix[ZX_K_X] = !is_up;
        is_ss_used = is_shift;
      }
      break;

    // Keypad * -> SS+B
    case PS2_KP_STAR:
      matrix[ZX_K_SS] = !is_up;
      matrix[ZX_K_B] = !is_up;
      break;

    // Keypad - -> SS+J
    case PS2_KP_MINUS:
      matrix[ZX_K_SS] = !is_up;
      matrix[ZX_K_J] = !is_up;
      break;

    // Keypad + -> SS+K
    case PS2_KP_PLUS:
      matrix[ZX_K_SS] = !is_up;
      matrix[ZX_K_K] = !is_up;
      break;

    // Tab
    case PS2_TAB:
      matrix[ZX_K_CS] = !is_up;
      matrix[ZX_K_I] = !is_up;
      process_capsed_key(scancode, is_up);
      break;

    // CapsLock
    case PS2_CAPS:
      matrix[ZX_K_SS] = !is_up;
      matrix[ZX_K_CS] = !is_up;
      process_capsed_key(scancode, is_up);
      break;

    // PgUp -> CS+3 for ZX
    case PS2_PGUP:
      matrix[ZX_K_CS] = !is_up;
      matrix[ZX_K_3] = !is_up;
      process_capsed_key(scancode, is_up);
      break;

    // PgDn -> CS+4 for ZX
    case PS2_PGDN:
      matrix[ZX_K_CS] = !is_up;
      matrix[ZX_K_4] = !is_up;
      process_capsed_key(scancode, is_up);
      break;

    // Scroll Lock -> Turbo
    case PS2_SCROLL: 
      if (is_up) {
        if (turbo == 0x0) {
          turbo = 0x01;
        } else if (turbo == 0x01) {
          turbo = 0x02;
        } else {
          turbo = 0x0;
        }

        is_turbo = (turbo > 0) ? true : false;
        eeprom_store_byte(EEPROM_TURBO_ADDRESS, turbo);
        matrix[ZX_K_TURBO0] = bitRead(turbo, 0);
        matrix[ZX_K_TURBO1] = bitRead(turbo, 1);
        matrix[ZX_K_TURBO] = is_turbo;
      }
    break;

    // Pause -> Wait
    case PS2_PAUSE:
      if (is_up) {
        is_wait = !is_wait;
        matrix[ZX_K_WAIT] = is_wait; 
      }
    break;

    // F1 -Rom bank 0
    case PS2_F1:
      if (is_up) {
        set_rombank(0);
      }
    break;

    // F2 -Rom bank 1
    case PS2_F2:
      if (is_up) {
        set_rombank(1);
      }
    break;

    // F3 -Rom bank 2
    case PS2_F3:
      if (is_up) {
        set_rombank(2);
      }
    break;

    // F4 -Rom bank 3
    case PS2_F4:
      if (is_up) {
        set_rombank(3);
      }
    break;

    // F5 -Rom bank 4
    case PS2_F5:
      if (is_up) {
        set_rombank(4);
      }
    break;

    // F6 -Rom bank 5
    case PS2_F6:
      if (is_up) {
        set_rombank(5);
      }
    break;

    // F7 -Rom bank 6
    case PS2_F7:
      if (is_up) {
        set_rombank(6);
      }
    break;

    // F8 -Rom bank 7
    case PS2_F8:
      if (is_up) {
        set_rombank(7);
      }
    break;

    // F11 - RESET
    case PS2_F11:
      if (is_up) {
        is_ctrl = false;
        is_alt = false;
        is_del = false;
        is_shift = false;
        is_ss_used = false;
        capsed_keys_size = 0;
        do_reset();        
      }
    break;

    // F12 -> Magick button
    case PS2_F12:
      if (is_up) {
        do_magick();
      }
    break;
  }

  if (is_ss_used and capsed_keys_size == 0) {
      matrix[ZX_K_CS] = false;
  }

  // Ctrl+Alt+Del -> RESET
  if (is_ctrl && is_alt && is_del) {
    is_ctrl = false;
    is_alt = false;
    is_del = false;
    is_shift = false;
    is_ss_used = false;
    capsed_keys_size = 0;
    do_reset();
  }

  // Ctrl+Alt+Bksp -> REINIT controller
  if (is_ctrl && is_alt && is_bksp) {
      is_ctrl = false;
      is_alt = false;
      is_bksp = false;
      is_shift = false;
      is_ss_used = false;
      capsed_keys_size = 0;
      clear_matrix(ZX_MATRIX_SIZE);
      matrix[ZX_K_RESET] = true;
      transmit_keyboard_matrix();
      matrix[ZX_K_S] = true;
      transmit_keyboard_matrix();
      delay(500);
      matrix[ZX_K_RESET] = false;
      transmit_keyboard_matrix();
      delay(500);
      matrix[ZX_K_S] = false;
  }

   // clear flags
   is_up = 0;
   if (is_e1) {
    is_e1 = 0;
   } else {
     is_e = 0;
   }
}

uint8_t get_matrix_byte(uint8_t pos)
{
  uint8_t result = 0;
  for (uint8_t i=0; i<8; i++) {
    uint8_t k = pos*8 + i;
    if (k < ZX_MATRIX_FULL_SIZE) {
      bitWrite(result, i, matrix[k]);
    }
  }
  return result;
}

void spi_send(uint8_t addr, uint8_t data) 
{
    uint8_t in_cmd = 0;
    uint8_t in_data = 0;

    SPI.beginTransaction(settingsA);
    digitalWrite(PIN_SS, LOW);
    //uint8_t cmd = SPI.transfer(addr); // command (1...6)
    //uint8_t res = SPI.transfer(data); // data byte
    in_cmd = SPI.transfer(addr); // command (1...6)
    in_data = SPI.transfer(data); // data byte
    digitalWrite(PIN_SS, HIGH);
    SPI.endTransaction();

    if (in_cmd == CMD_INIT) {
      init_done = true;
    }
}

// transmit keyboard matrix from AVR to CPLD side via SPI
void transmit_keyboard_matrix()
{
    uint8_t bytes = 8;
    for (uint8_t i=0; i<bytes; i++) {
      uint8_t data = get_matrix_byte(i);
      spi_send(i+1, data);
    }
}

// transmit keyboard macros (sequence of keyboard clicks) to emulate typing some special symbols [, ], {, }, ~, |, `
void send_macros(uint8_t pos)
{
  clear_matrix(ZX_MATRIX_SIZE);
  transmit_keyboard_matrix();
  delay(20);
  matrix[ZX_K_CS] = true;
  transmit_keyboard_matrix();
  delay(20);
  matrix[ZX_K_SS] = true;
  transmit_keyboard_matrix();
  delay(20);
  matrix[ZX_K_SS] = false;
  transmit_keyboard_matrix();
  delay(20);
  matrix[pos] = true;
  transmit_keyboard_matrix();
  delay(20);
  matrix[ZX_K_CS] = false;
  matrix[pos] = false;
  transmit_keyboard_matrix();
  delay(20);
}

void do_init_reset()
{
  clear_matrix(ZX_MATRIX_SIZE);
  matrix[ZX_K_SP] = true;
  matrix[ZX_K_RESET] = true;
  transmit_keyboard_matrix();
  delay(500);
  matrix[ZX_K_RESET] = false;
  transmit_keyboard_matrix(); 
  delay(200);
  matrix[ZX_K_SP] = false;
  transmit_keyboard_matrix();  
}

void do_reset()
{
  clear_matrix(ZX_MATRIX_SIZE);
  matrix[ZX_K_RESET] = true;
  transmit_keyboard_matrix();
  delay(500);
  matrix[ZX_K_RESET] = false;
  transmit_keyboard_matrix();  
}

void do_magick()
{
  matrix[ZX_K_MAGICK] = true;
  transmit_keyboard_matrix();
  delay(500);
  matrix[ZX_K_MAGICK] = false;
  transmit_keyboard_matrix();
}

void set_rombank(byte bank)
{
  rom_bank = bank;
  eeprom_store_byte(EEPROM_ROMBANK_ADDRESS, rom_bank);
  matrix[ZX_K_ROMBANK0] = bitRead(rom_bank, 0);
  matrix[ZX_K_ROMBANK1] = bitRead(rom_bank, 1);
  matrix[ZX_K_ROMBANK2] = bitRead(rom_bank, 2);
  do_reset();
}

void clear_matrix(int clear_size)
{
    // all keys up
  for (int i=0; i<clear_size; i++) {
      matrix[i] = false;
  }
}

bool eeprom_restore_bool(int addr, bool default_value)
{
  byte val;  
  val = EEPROM.read(addr);
  if ((val == EEPROM_VALUE_TRUE) || (val == EEPROM_VALUE_FALSE)) {
    return (val == EEPROM_VALUE_TRUE) ? true : false;
  } else {
    EEPROM.update(addr, (default_value ? EEPROM_VALUE_TRUE : EEPROM_VALUE_FALSE));
    return default_value;
  }
}

byte eeprom_restore_byte(int addr, byte default_value)
{
  return EEPROM.read(addr);
}

void eeprom_store_bool(int addr, bool value)
{
  byte val = (value ? EEPROM_VALUE_TRUE : EEPROM_VALUE_FALSE);
  EEPROM.update(addr, val);
}

void eeprom_store_byte(int addr, byte value)
{
  EEPROM.update(addr, value);
}

void eeprom_restore_values()
{
  rom_bank = eeprom_restore_byte(EEPROM_ROMBANK_ADDRESS, 0);
  turbo = eeprom_restore_byte(EEPROM_TURBO_ADDRESS, 0);
  if (rom_bank > 7) {
    rom_bank = 0;
    eeprom_store_byte(EEPROM_ROMBANK_ADDRESS, rom_bank);
  }
  if (turbo > 0x02) {
    turbo = 0;
    eeprom_store_byte(EEPROM_TURBO_ADDRESS, turbo);
  }
  is_turbo = (turbo > 0) ? true : false;
  matrix[ZX_K_TURBO0] = bitRead(turbo, 0);
  matrix[ZX_K_TURBO1] = bitRead(turbo, 1);
  matrix[ZX_K_TURBO] = is_turbo;
  matrix[ZX_K_ROMBANK0] = bitRead(rom_bank, 0);
  matrix[ZX_K_ROMBANK1] = bitRead(rom_bank, 1);
  matrix[ZX_K_ROMBANK2] = bitRead(rom_bank, 2);
}

void eeprom_store_values()
{
  eeprom_store_byte(EEPROM_TURBO_ADDRESS, turbo);
  eeprom_store_byte(EEPROM_ROMBANK_ADDRESS, rom_bank);
}

// initial setup
void setup()
{
  SPI.begin();

  pinMode(PIN_SS, OUTPUT);
  digitalWrite(PIN_SS, HIGH);

  pinMode(LED_PWR, OUTPUT);
  pinMode(LED_KBD, OUTPUT);
  pinMode(LED_TURBO, OUTPUT);
  pinMode(LED_ROMBANK, OUTPUT);
  pinMode(LED_PAUSE, OUTPUT);
  pinMode(AUDIO_OFF, OUTPUT);

// set up pins for kempston joy
#if JOY_TYPE==JOY_KEMPSTON
  pinMode(JOY_UP, INPUT_PULLUP);
  pinMode(JOY_DOWN, INPUT_PULLUP);
  pinMode(JOY_LEFT, INPUT_PULLUP);
  pinMode(JOY_RIGHT, INPUT_PULLUP);
  pinMode(JOY_FIRE, INPUT_PULLUP);
  pinMode(JOY_FIRE2, INPUT_PULLUP);
  pinMode(JOY_FIRE3, INPUT_PULLUP);
#endif

  digitalWrite(LED_PWR, HIGH);
  digitalWrite(LED_KBD, HIGH);
  digitalWrite(LED_TURBO, LOW);
  digitalWrite(LED_ROMBANK, LOW);
  digitalWrite(LED_PAUSE, LOW);
  digitalWrite(AUDIO_OFF, LOW);

  // ps/2
  pinMode(PIN_KBD_CLK, INPUT_PULLUP);
  pinMode(PIN_KBD_DAT, INPUT_PULLUP);

  // nmi button
  pinMode(PIN_BTN_NMI, INPUT_PULLUP);

  // clear full matrix
  clear_matrix(ZX_MATRIX_FULL_SIZE);

  // restore saved modes from EEPROM
  eeprom_restore_values();

  digitalWrite(LED_TURBO, (turbo != 0) ? HIGH : LOW);
  digitalWrite(LED_ROMBANK, (rom_bank != 0) ? HIGH: LOW);

  kbd.begin(PIN_KBD_DAT, PIN_KBD_CLK);

  // waiting for init
  while (!init_done) {
    spi_send(CMD_NONE, 0x00);
  }

  do_init_reset();

  digitalWrite(LED_KBD, LOW);
}


// main loop
void loop()
{
  unsigned long n = millis();
  
  if (kbd.available()) {
    int c = kbd.read();
    tl = n;
    digitalWrite(LED_KBD, HIGH);
    fill_kbd_matrix(c);
  }

// read sega joystick
#if JOY_TYPE==JOY_SEGA
  joy_current_state = joystick.getState();
  if (joy_current_state != joy_last_state) {
    matrix[ZX_JOY_UP] = !(joy_current_state & SC_BTN_UP);
    matrix[ZX_JOY_DOWN] = !(joy_current_state & SC_BTN_DOWN);
    matrix[ZX_JOY_LEFT] = !(joy_current_state & SC_BTN_LEFT);
    matrix[ZX_JOY_RIGHT] = !(joy_current_state & SC_BTN_RIGHT);
    matrix[ZX_JOY_FIRE] = !(joy_current_state & SC_BTN_B);
    matrix[ZX_JOY_FIRE2] = !(joy_current_state & SC_BTN_C);
    matrix[ZX_JOY_FIRE3] = !(joy_current_state & SC_BTN_A);
    matrix[ZX_JOY_FIRE4] = !(joy_current_state & SC_BTN_START);
    matrix[ZX_JOY_X] = !(joy_current_state & SC_BTN_X);
    matrix[ZX_JOY_Y] = !(joy_current_state & SC_BTN_Y);
    matrix[ZX_JOY_Z] = !(joy_current_state & SC_BTN_Z);
    matrix[ZX_JOY_MODE] = !(joy_current_state & SC_BTN_MODE);
    joy_last_state = joy_current_state;    
  }
#else
  // read kempston joystick
  matrix[ZX_JOY_UP] = digitalRead(JOY_UP);
  matrix[ZX_JOY_DOWN] = digitalRead(JOY_DOWN);
  matrix[ZX_JOY_LEFT] = digitalRead(JOY_LEFT);
  matrix[ZX_JOY_RIGHT] = digitalRead(JOY_RIGHT);
  matrix[ZX_JOY_FIRE] = digitalRead(JOY_FIRE);
  matrix[ZX_JOY_FIRE2] = digitalRead(JOY_FIRE2);
  matrix[ZX_JOY_FIRE3] = true;
  matrix[ZX_JOY_FIRE4] = true;
  matrix[ZX_JOY_X] = true;
  matrix[ZX_JOY_Y] = true;
  matrix[ZX_JOY_Z] = true;
  matrix[ZX_JOY_MODE] = true;
#endif

  if (digitalRead(PIN_BTN_NMI) == LOW) {
    do_magick();
  }

  // transmit kbd always
  transmit_keyboard_matrix();

  // update leds
  if (n - tl >= 200) {
    digitalWrite(LED_KBD, LOW);
    tl = n;
  }

  if (n - tb >= 500) {
    blink = !blink;
    tb = n;
  }

  if (turbo == 0x02) {
    digitalWrite(LED_TURBO, blink ? HIGH : LOW);
  } else {
    digitalWrite(LED_TURBO, (turbo != 0) ? HIGH : LOW);
  }

  digitalWrite(LED_PAUSE, is_wait ? HIGH: LOW);
  digitalWrite(AUDIO_OFF, is_wait ? HIGH: LOW);
  digitalWrite(LED_ROMBANK, rom_bank != 0 ? HIGH : LOW);
  
}

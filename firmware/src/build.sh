#!/bin/sh

export PATH=/opt/altera/quartus/bin:$HOME/.platformio/penv/bin:$PATH

echo "Building AVR sources"

cd avr_kbd

pio run -t clean
export PLATFORMIO_BUILD_FLAGS="-DJOY_TYPE=0 -Wall"
pio run
cp .pio/build/ATmega8/firmware.hex ../../release/avr_kbd.hex

pio run -t clean
export PLATFORMIO_BUILD_FLAGS="-DJOY_TYPE=1 -Wall"
pio run
cp .pio/build/ATmega8/firmware.hex ../../release/avr_kbd_sega.hex

pio run -t clean

echo "Done"

#exit

cd ..

echo "Building Speccy FPGA sources"

cd fpga/speccy/syn

make clean
make all
make jic

cp firmware_top.jic ../../../../release/firmware_speccy.jic

make clean

echo "Done"

cd ../../../


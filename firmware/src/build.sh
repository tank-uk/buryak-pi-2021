#!/bin/sh

export PATH=/opt/altera/quartus/bin:$HOME/.platformio/penv/bin:$PATH

echo "Building AVR sources"

cd avr_kbd

pio run -t clean
pio run

cp .pio/build/ATmega8/firmware.hex ../../release/avr_kbd.hex

pio run -t clean

echo "Done"

cd ..

echo "Building FPGA sources"

cd fpga/syn

make clean
make all
make jic

cp firmware_top.jic ../../../release/firmware.jic

make clean

echo "Done"

cd ../../


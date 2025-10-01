Example Single Key MicroZig Development - RP2040

# Introduction
A example project which enables usb based logging and quick reset/load (without pressing buttons).
It requires - beyond zig - python, py_serial and the picotool (for loading)

It uses the cdc implementation in microzig to communicate through USB and watches for a "magic sequence" to force the RP2040 to reset to the bootloader (for loading new uCode)
It enables very fast (I think) development loop on the RP2040 with only USB connected - single key build and load. 

This also has some fixes/ workarounds to avoid loosing data with very fast USB cdc writes.  
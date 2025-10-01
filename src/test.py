# Just runs zig build load
# Not great at VS code and I like single button build/run.
import os, sys
import subprocess 

sys.tracebacklimit = 2

def system(cmd):
    ret = os.system(cmd)
    if ret:
        raise RuntimeError(f"Command Failed: {cmd} \n    ret:{ret}")

### Serial stuff
import serial
import serial.tools.list_ports
from serial import SerialException
import time
import threading

def find_serial():
    ports = serial.tools.list_ports.comports()
    # Find RP2040 VIDPID (or whatever we decide to search for) 
    for portinfo in ports:
        if portinfo.vid:
            print(hex(portinfo.vid), hex(portinfo.pid))
        if portinfo.vid == 0x2e8a and portinfo.pid == 0xa:
            return portinfo
    raise RuntimeError("Serial Port Not Found")



def try_connect(attempts=10):
    print("Searching for CDC Device")
    for i in range(attempts):
        try:
            portinfo = find_serial()
        except (RuntimeError, SerialException):
            if i > 4:
                print(f"Failed to find serial port.  Retrying ({i+1}) in {i/2} seconds...")
            time.sleep(i/3)
        else:
            break
    else:
        ports = serial.tools.list_ports.comports()
        print("\nAvalible Ports:")
        for portinfo in ports:
            if portinfo.vid:
                print(portinfo.description, hex(portinfo.vid), hex(portinfo.pid))
        raise RuntimeError("Could not find CDC Device!")
    ser = SERCONTROL(serial.Serial(portinfo.device, baudrate=115200))
    return ser


class SERCONTROL:
    def __init__(self, ser):
        self.ser = ser
        self.log_flag = True
        self.stdo_th = threading.Thread(target=self._read_buffer, daemon=True)
        self.stdo_th.start()

    def _read_buffer(self):
        # TODO: how can we make it more clear that this is comming from device?
        while self.log_flag:
            try:
                v = self.ser.read_all()
                if v:
                    print('\033[96m'+ v.decode(errors="replace")+ '\033[0m',end="")
                time.sleep(.01) 
            except OSError:
                print("Lost Connection To Device!")
                break

    def write_cmd(self, cmd, data):
        # 4 bytes data
        if (cmd & 0b1100_0000) == 0b1100_0000:
            assert data <= 0xFFFF_FFFF, f"Data too big:{hex(cmd)}: {hex(data)}"
            data_b = data.to_bytes(4, 'little')
            self.write(bytes([cmd])+data_b)
        # Two bytes data
        elif cmd & 0b1000_0000: 
            assert data <= 0xFFFF, f"Data too big:{hex(cmd)}: {hex(data)}"
            data_b = data.to_bytes(2, 'little')
            self.write(bytes([cmd])+data_b)
        else:
            assert data <= 0xF, f"Data too big:{hex(cmd)}: {hex(data)}"
            self.write(bytes([cmd<<4 | data]))

    def write(self, data_b):
        self.ser.write(data_b)


if __name__ == "__main__":
    system("clear")
    # system('zig build load')
    try:
        ser = try_connect(1)
        print("Attempting Reboot to Bootloader")
        ser.log_flag = False
        ser.write(b'magiccode1234')
        time.sleep(2) # TODO: wait for some event showing it's ready rather than this and move it into the load step
    except:
        pass

    system('zig build load')
    # p = subprocess.Popen(["kitty", "python", "src/debug_picoprobe.py"])
    try:
        time.sleep(0)
        ser = try_connect(10)
        # for i in range(10):
        #     time.sleep(1)
        #     ser.write(f"test {i}".encode())
    finally:
        input("Waiting...\n")
        # p.terminate()

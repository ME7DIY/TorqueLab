import socket
import struct

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('127.0.0.1', 4444))

while True:
    data = sock.recv(256)
    if not data:
        break

    fmt = 'I4sH2b7f2I3f16s16sI'
    unpacked = struct.unpack(fmt, data)

    time       = unpacked[0]
    car        = unpacked[1]
    flags      = unpacked[2]
    gear       = unpacked[3] - 1  # 0=reverse, 1=neutral, 2=first → subtract 1 for normal display
    speed      = unpacked[5] * 3.6
    rpm        = unpacked[6]
    turbo      = unpacked[7]
    engtemp    = unpacked[8]
    fuel       = unpacked[9] * 100
    oiltemp    = unpacked[11]
    throttle   = unpacked[14]
    brake      = unpacked[15]
    clutch     = unpacked[16]

    print(f"RPM: {rpm:.0f} | Speed: {speed:.1f}km/h | Gear: {gear} | Boost: {turbo:.2f}bar | Throttle: {throttle:.2f} | Brake: {brake:.2f} | Fuel: {fuel:.1f}% | OilTemp: {oiltemp:.1f}C | EngTemp: {engtemp:.1f}C")
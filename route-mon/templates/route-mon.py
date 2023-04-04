#!/usr/bin/python3

import time, os, sys, re, subprocess

GATEWAYS = {{ route_mon_gws | to_json }}
ROUTES = {{ route_mon_routes | to_json }}
CHECK_INTERVAL = {{ route_mon_interval | default(1) }}

def get_alive_gws():
    fping_cmd = f"fping -t500 {' '.join(GATEWAYS)}"
    #result = subprocess.run(fping_cmd, shell=True, capture_output=True, text=True)
    result = subprocess.run(fping_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    alive_gws = re.findall(r"(\d+\.\d+\.\d+\.\d+) is alive", result.stdout)
    return alive_gws

def is_route_set(network, gw):
    ip_cmd = f"ip route show {network}"
    #result = subprocess.run(ip_cmd, shell=True, capture_output=True, text=True)
    result = subprocess.run(ip_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    return f"via {gw} dev" in result.stdout

def get_iface_for_gw(gw_ip):
    ip_cmd = f"ip route get {gw_ip}"
    #result = subprocess.run(ip_cmd, shell=True, capture_output=True, text=True)
    result = subprocess.run(ip_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    match = re.search(r"dev (\S+)", result.stdout)
    if match:
        return match.group(1)

def set_route(net, gw):
    iface = get_iface_for_gw(gw)
    if gw and iface:
      print(net, "routed via", iface)
      os.system(f"ip route replace {net} via {gw} dev {iface}")
    else:
      print(net, "blackholed")
      os.system(f"ip route replace blackhole {net}")


prev_alive = []
print("restarted")
while True:
  time.sleep(CHECK_INTERVAL)
  active_gw = None
  alive_gws = get_alive_gws()
  route_set = False

  if alive_gws != prev_alive:
    print("alive gws", alive_gws)
    prev_alive = alive_gws

  # find active gateway
  for gw in GATEWAYS:
    if is_route_set(ROUTES[0], gw):
      active_gw = gw

  # is active gw still alive?
  if active_gw:
    if active_gw in alive_gws:
      route_set = True
      continue
    else:
      print("active gw",active_gw,"lost")

  # select alive gw
  for gw in alive_gws:
    for net in ROUTES:
      set_route(net, gw)
    print("set new route via", gw)
    route_set = True
    continue

  # or null route
  if active_gw and not route_set:
    for net in ROUTES:
      set_route(net, None)

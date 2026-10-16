from ipaddress import ip_address, ip_network
from ansible.errors import AnsibleFilterError

def firewall_normalize_addrs(rule, attr, firewall_objects):
    if attr not in rule:
        return ["ANY"]

    raw = rule[attr]
    if isinstance(raw, str):
        attrs = [raw]
    else:
        attrs = raw

    results = []
    for item in attrs:
        trimmed = item.strip()
        results.extend(_lookup_object(trimmed, firewall_objects))
    return sorted(set(results))

def firewall_normalize_ports(rule, proto):
    if 'proto' not in rule:
        return ['ANY']

    ports = rule['proto'][proto]
    if ports is None:
        return ['ANY']

    if isinstance(ports, str):
        ports = [p.strip() for p in ports.replace(' ', '').split(',') if p.strip()]
    elif isinstance(ports, int):
        ports = [ports]
    elif not isinstance(ports, list):
        ports = list(ports)

    return sorted(set(ports))

def firewall_render_rule():
    return

def _is_ip_or_network(value):
    try:
        ip_address(value)
        return True
    except ValueError:
        pass
    try:
        ip_network(value, strict=False)
        return True
    except ValueError:
        return False

def _lookup_object(name, firewall_objects):
    if name in firewall_objects:
        obj = firewall_objects[name]
    else:
        obj = name

    if isinstance(obj, str):
        entries = [obj]
    else:
        entries = list(obj)

    results = []
    for item in entries:
        trimmed = item.strip()
        if trimmed in firewall_objects:
            results.extend(_lookup_object(trimmed, firewall_objects))
        else:
            if _is_ip_or_network(trimmed):
                results.append(trimmed)
            else:
                raise AnsibleFilterError( f"firewall_object {trimmed} not defined. using dns names is not allowed.")
    return results

class FilterModule(object):
    def filters(self):
        return {
            'firewall_normalize_addrs': firewall_normalize_addrs,
            'firewall_normalize_ports': firewall_normalize_ports,
            'firewall_render_rule': firewall_render_rule,
        }

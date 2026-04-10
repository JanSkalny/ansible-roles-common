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
        if trimmed in firewall_objects:
            results.extend(_lookup_object(trimmed, firewall_objects))
        else:
            results.append(trimmed)
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

def _lookup_object(name, firewall_objects):
    obj = firewall_objects[name]
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
            results.append(trimmed)
    return results

class FilterModule(object):
    def filters(self):
        return {
            'firewall_normalize_addrs': firewall_normalize_addrs,
            'firewall_normalize_ports': firewall_normalize_ports,
        }


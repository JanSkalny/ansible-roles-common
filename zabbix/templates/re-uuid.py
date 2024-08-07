#!/usr/bin/env python3

import sys
import re
import uuid

def replace_uuids(input_text):
    pattern = r'uuid:\s*([a-f0-9-]+)$'
    return re.sub(pattern, lambda x: f'uuid: {uuid.uuid4().hex}', input_text, flags=re.MULTILINE)

if __name__ == "__main__":
    input_text = sys.stdin.read()
    modified_text = replace_uuids(input_text)
    sys.stdout.write(modified_text)


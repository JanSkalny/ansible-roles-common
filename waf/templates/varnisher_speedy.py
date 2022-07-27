#!/usr/bin/env python

import subprocess, json, syslog

p = subprocess.Popen(["{{ waf_varnishlog_executable }}","-A"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=-1)

def req_flush(req):
  s = json.dumps(req)
  #if 'log' in req:
  #  print s
  syslog.syslog(s)
  req = {}

def req_add(req, field, val, append=False):
  if field not in req:
    req[field] = val
  elif append:
    req[field] += " - "+val

in_req = False
req = {}
while p.poll() is None:
  line = p.stdout.readline()
  cmd = line[4:].strip()
  #print "cmd", cmd

  # start of request
  if cmd[:14] == "<< Request  >>":
    req = {}
    in_req = True
    continue

  # ignore non-request line
  if not in_req:
    continue

  # end of request
  if cmd == "End":
    in_req = False
    req_flush(req)
    continue

  # stop processing headers after log was found
  if 'log' in req:
    continue

  if cmd[:21] == "ReqHeader      X-VSF-":
    if   cmd[15:31] == "X-VSF-Actual-IP:":
      req_add(req, 'ip', cmd[32:])
    elif cmd[15:30] == "X-VSF-RuleName:":
      req_add(req, 'vsf_rule_name', cmd[31:])
    elif cmd[15:28] == "X-VSF-RuleID:":
      req_add(req, 'vsf_rule_id', cmd[29:])
#    elif cmd[15:30] == "X-VSF-Response:":
#      req_add(req, 'vsf_response', cmd[31:])
    else:
      continue
  elif cmd[:25] == "RespHeader     X-Varnish:":
    req_add(req, 'xid', int(cmd[26:]))
  elif cmd[:20] == "ReqHeader      Host:":
    req_add(req, 'host', cmd[21:])
  elif cmd[:10] == "RespStatus":
    req_add(req, 'http_status', int(cmd[15:]))
#  elif cmd[:10] == "RespReason":
#    req_add(req, 'http_reason', cmd[15:], True)
  elif cmd[:7] ==  "VCL_Log":
    req_add(req, 'log', cmd[15:])
  elif cmd[:6] ==  "ReqURL":
    req_add(req, 'url', cmd[15:])
  else:
    continue

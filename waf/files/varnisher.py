#!/usr/bin/env python

import subprocess, re, json, os, time, random, string

p = subprocess.Popen(["/usr/bin/varnishlog","-a"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=-1)
block_dir = '/tmp/varnish_bls/'

if not os.path.exists(block_dir):
    os.makedirs(block_dir)

def randomword(length):
   return ''.join(random.choice(string.lowercase) for i in range(length))

ip = None
url = None
log = None
while p.poll() is None:
	line = p.stdout.readline()
	
	cmd = line[4:]
	#print "cmd", cmd

	# ReqHeader      X-VSF-Actual-IP: 192.168.122.1
	m = re.match('.*X-VSF-Actual-IP: (.*)$', cmd)
	if m:
		ip = m.group(1)

	#ReqURL         /?id='UNION%20SELECT%201
	m = re.match('ReqURL[ ]+(.*)$', cmd)
	if m:
		url = m.group(1)

	#VCL_Log        security.vcl alert xid:32833 HTTP/1.1 [-encoded.sql-5][127.0.0.1] 192.168.122.251/?id='UNION%20SELECT%201 (Wget/1.17.1 (linux-gnu)) (SQL Injection)
	#m = re.match('VCL_Log[ ]+(.*)$', cmd)
	#if m:
	#	log = m.group(1)

	#RespStatus     777
	m = re.match('RespStatus[ ]+([0-9]+)$', cmd)
	if m and ip:
		status = int(m.group(1))
		if status == 777:
			print "HACK! from ip", ip, "at url", url
			with open(block_dir+randomword(20)+'.json', 'w') as outfile:
			    json.dump({ 'addr': ip, 'url': url, "time": time.time() }, outfile)
		ip = None
		url = None



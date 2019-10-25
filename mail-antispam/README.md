antispam

DCC

mkdir -p /opt/dcc/
cd /tmp/
wget http://www.dcc-servers.net/dcc/source/dcc-dccproc.tar.Z
tar xvf dcc-dccproc.tar.Z
cd dcc-dccproc-1.3.158/
chown -R amavis:amavis /opt/dcc/
ln -s /opt/dcc/libexec/dccifd /usr/local/bin/dccifd


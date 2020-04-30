#!/bin/bash

fail() {
	echo "$*" 1>&2
	exit 1
}

set_iface_affinity() {
	[[ $( cat /proc/interrupts  | grep $1 | wc -l ) == "1" ]] || fail "too many irqs for $1"
	IRQ=$( cat /proc/interrupts  | grep $1 | awk '{print $1}' | cut -d: -f1)
	echo $2 > /proc/irq/$IRQ/smp_affinity
}

# pin all irqs to first core of first cpu
for D in $( ls /proc/irq ); do
	if [[ -x "/proc/irq/$D" && $D != "0" ]]; then
		echo $D
		echo 1 > /proc/irq/$D/smp_affinity
	fi
done

# core 8
set_iface_affinity sensor0 100

# core 9
#set_iface_affinity sensor1 200

# pin rcu processes to 0
for PID in $( pgrep rcu ); do 
	taskset -pc 0 $PID
done

echo 1 > /sys/bus/workqueue/devices/writeback/cpumask
echo 0 > /sys/bus/workqueue/devices/writeback/numa

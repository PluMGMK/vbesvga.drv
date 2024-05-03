#!/bin/bash
killall picocom # In case I forget to close it manually…
kercmd="set line /dev/ttyUSB0, set speed 115200,"
for fn in "$@"
do
	ufn=${fn^^}
	kercmd="$kercmd get $fn $ufn,"
done
kercmd="$kercmd purge, bye, exit"
echo "Starting kermit with command \"$kercmd\""
kermit -C "$kercmd"

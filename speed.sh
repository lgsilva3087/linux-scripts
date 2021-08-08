#! /bin/sh

#Disables BD PROCHOT on my CPU (DELL Laptop)

echo "Start"

echo $(cat /proc/cpuinfo | grep "MHz") 


value=$(rdmsr 0x1FC)
echo "Initial value: $value" 

modprobe msr
wrmsr 0x1FC 2

value=$(rdmsr 0x1FC)
echo "Final value: $value"

echo $(cat /proc/cpuinfo | grep "MHz") 

echo "End"

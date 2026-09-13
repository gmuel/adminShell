#!/bin/bash

for i in $(ls /home ); do
	closeEncDS.sh $i
done

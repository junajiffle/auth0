#!/bin/bash
echo "Enter the app name"
read app
if [[ "$app" == "app1" ]];
then
	 lb=auth1
	echo "Load balancer for $app is : $lb"
elif [[ "$app" == "app2" ]]; then
	lb=auth0
	echo "Load balancer for $app is : $lb"
elif [[ "app" == "app3" ]]; then
	lb=auth3
	echo "Load balancer for $app is : $lb"
else
	echo "Invalid application name"
	exit 1
fi


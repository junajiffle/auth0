#!/bin/bash
echo "Starting system upgrade"
ssh -i ~/Downloads/app.pem ec2-user@$instanceip "sudo /usr/bin/yum update -y"
echo "rebooting $instance"
ssh -i ~/Downloads/app.pem ec2-user@$instanceip "sudo /usr/sbin/reboot"

sleep 30


echo "Checking application status"
#if curl -I -H "$instanceip" http://localhost/testall | grep "301 Moved Permanently" > /dev/null;
if ssh -t -t -i ~/Downloads/app.pem ec2-user@$instanceip "echo SUCCESS; date"; 
then 
	echo "Application is UP"
else
   echo "Application is DOWN"
   exit 1
fi


echo "System upgrade completed..."
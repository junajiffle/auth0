#!/bin/bash
echo "Enter the type of environment. Type 'primary' if it is a primary environment, else type 'secondary'"
read env
. ./get_lb.sh

#Get the number of instances attached to LB
instances_id=($(aws elb describe-load-balancers --load-balancer-name $lb  --query LoadBalancerDescriptions[].Instances[].InstanceId  --output=text))
instance_length=${#instances_id[@]}

#Check if any instance attached to LB"
if [ $instance_length == 0 ]
then
	echo "No instances attached to $lb"
    exit 1
fi
for (( j=0; j<$instance_length; j++ ))
do
instance=${instances_id[$j]}
instanceip=($(aws ec2 describe-instances --instance-ids $instance --query Reservations[].Instances[].PublicIpAddress --output=text))

#removing target from ami
echo "Removing node $instance from the load balancer."
aws elb deregister-instances-from-load-balancer --load-balancer-name $lb --instances $instance

sleep 10

echo "Enter the AMI name to be created"
read name
d=$(date +%Y-%m-%d)
ami="$name $d"

#creating AMI for the instance
echo "Creating backup for $instance"
if [ $env == primary ]
then
   echo "Creating AMI with reboot"
   aws ec2 create-image --instance-id $instance --name "$ami" --description "Automated backup created for $instance"
else
   echo "Creating AMI without reboot"
   aws ec2 create-image --no-reboot --instance-id $instance --name "$ami" --description "Automated backup created for $instance"
fi
echo "Backup process completed...."

#Executing maintenance script
. ./maintenance.sh

#Adding target back to LB
echo "Adding target back to LB"
aws elb register-instances-with-load-balancer --load-balancer-name $lb --instances $instance

#Removing old AMIS
echo "Do you wish to remove old AMI?"
echo "type "yes" if need to remove old backups or "no""
read old
if [ $old == yes ]
then
	. ./backup_deletion.sh
	#echo "Enter the Id of the backup to be removed"
	#read "backup"
	#snapshot=($(aws ec2 describe-images --image-ids $backup | grep "SnapshotId" | cut -d: -f2 | sed -e 's/^ "//' -e 's/"$//'))
	#aws ec2 deregister-image --image-id $backup
	#echo "Deleted AMI $backup"
	#aws ec2 delete-snapshot --snapshot-id $snapshot
	#echo "Deleted snapshot $snapshot"
else
	echo "System maintenance completed successfully!"
fi
done


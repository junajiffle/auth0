#!/bin/bash
echo "Enter the environment. Type 'primary' if it is a primary region, else type 'secondary'"
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
aws elb deregister-instances-from-load-balancer --load-balancer-name $lb --instances $instance --output=text

sleep 10

ami="instance-$instance-`date +%d%b%y`"

#creating AMI for the instance
echo "Creating backup for $instance"
if [ $env == primary ]
then
  echo "Creating AMI with reboot"
  aws ec2 create-image --instance-id $instance --name "$ami" --description "Automated backup created for $instance" --output=text
elif [ $env == secondary ]
  then
  echo "Creating AMI without reboot"
  aws ec2 create-image --no-reboot --instance-id $instance --name "$ami" --description "Automated backup created for $instance" --output=text
else
  echo "No region $env found"
  exit 1
fi
echo "Backup process completed...."

#Executing maintenance script

updateandreboot ()
{
  echo "Starting sytem upgrade......"
  ssh -i ~/Downloads/app.pem ec2-user@$1 'sudo /usr/bin/yum update -y; sudo reboot'
  sleep 1m
  echo "Checking application status"
  responce=$(curl -I https://amazon.jifflenow.com  --write-out %{http_code} --output /dev/null --silent)
  echo "$responce"
  if [[ "$responce" == "200" ]]
  then 
    echo "Application is UP"
  else
    echo "Application is DOWN"
    exit 1
  fi
}

echo "Do you want to perform a system update?"
echo "Type 'yes'| 'no'"
read continue
if [ $continue = yes ]
then
updateandreboot $instanceip
else
  echo "No maintenance for $instance"
fi


#Adding target back to LB
echo "Adding target back to LB"
aws elb register-instances-with-load-balancer --load-balancer-name $lb --instances $instance

echo "Maintenance completed for $instance!"
done

#Removing old AMIS
echo "Do you wish to remove old AMI?"
echo "Type 'yes | no'"
read old
if [ $old == yes ]
then
  echo "Fetching AMI details ...."
	ami_array=($(aws ec2 describe-images --owners=488905371868 --query Images[].ImageId --output=text))
  array_length=${#ami_array[@]}
  for (( i=0; i<$array_length; i++ ))
  do
    image_id=${ami_array[$i]}
    image_name=($(aws ec2 describe-images --image-ids=$image_id  --query Images[].Name --output=text))
    image_date=($(aws ec2 describe-images --image-ids=$image_id  --query Images[].CreationDate --output=text | cut -d'T' -f1))
    imgdt=$(gdate -d $image_date +%s)
    current_date=$(date +%Y-%m-%d)
    todate=$(gdate -d $current_date +%s)
    echo $current_date
    if [ '$todate' -gt '$imgdt' ];
    then
      echo "Following AMI is found : $image_id"
      echo ""Image Name : $image_name""
      echo ""Image CreationDate : $image_date""
      aws ec2 describe-images --image-ids $image_id | grep "SnapshotId" | cut -d: -f2 | sed -e 's/^ "//' -e 's/"$//' > /tmp/snap.txt
      echo  ""Following are the snapshots associated with it : `cat /tmp/snap.txt`""
      echo  "Do you wish to proceed with deletion?. Type 'yes | no'"
      read proceed
      if [[ "$proceed" == "yes" ]]; 
      then
       echo  "Starting the Deregister of AMI... "
       aws ec2 deregister-image --image-id $image_id
       echo "Deleting the associated snapshots.... "
       for j in `cat /tmp/snap.txt`;do aws ec2 delete-snapshot --snapshot-id $j ; done
       sleep 3 
      fi
    else
      echo "Image $image_id not older than 30 days"
    fi
  done
fi



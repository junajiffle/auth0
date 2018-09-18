# AWS AMI Backup and Cleanup

This script is to automate the backup procedure for a 3 node HA appliance.

Note: Before running the script make sure that you have installed and configured aws-cli on the machine.
Please refer the link "https://docs.aws.amazon.com/cli/latest/userguide/installing.html" for setting up the AWS command line interface.


**Procedure for backup and cleanup:**

1) Remove a node from the load balancer.
2) Create an AMI from the node (with reboot for primary and without reboot for secondary).
3) Update and reboot the machine. Wait for the node "/testall" endpoint to return "OK"
4) Add the node back to the load balancer.
5) Remove the old backups and AMIs along with the EBS volume snapshots that are no longer needed.

The script will ask for a user input to enter the environment name. If it is primary, then the complete actions will be performed on primary nodes and similarly for secondary.

Once the environment is set, next the script asks for the application name. The "get_lb.sh" script maps the application name to its corresponding loadbalancer(LB). There is no need of checking into the console for getting the LB name.

**Sample output:**
```
Enter the environment. Type 'primary' if it is a primary region, else type 'secondary'
primary
Enter the app name
app2
Load balancer for app2 is : xxxx
```

**1.Remove a node from the load balancer.**

We can get the list of instances attached to the Lb using the command "aws elb describe-load-balancers". Create an array which holds the "instance-id" of the instances. A "for" loop in shell script can be used to perform maintenance on each instance one at a time. 

*Command:*
```
#Get the number of instances attached to LB
instances_id=($(aws elb describe-load-balancers --load-balancer-name $lb  --query LoadBalancerDescriptions[].Instances[].InstanceId  --output=text))
```
Before proceeding to deregister AMI from LB. Script will check for the number of instances attached to the LB. If it is zero the script will exit saying "No instances attached to LB".

*Command:*
```
instance_length=${#instances_id[@]}
if [ $instance_length == 0 ]
then
  echo "No instances attached to $lb"
  exit 1
fi
```
If instance count is non-zero the the script proceeds for deregistering instance from LB and create AMI.

*Command:*
```
aws elb deregister-instances-from-load-balancer --load-balancer-name $lb --instances $instance --output=text
```
**Sample output:**
```
Removing node i-03ece495a76794506 from the load balancer.
INSTANCES	i-0c137c56b308ce3c5
```

**2.Create an AMI from the node (with reboot for primary and without reboot for secondary).**

Next is to create an AMI for the instance which has been removed from the LB now. If this is a node in primary environment, AMI should be created with reboot. By default, Amazon EC2 attempts to shut down and reboot the instance before creating the image. You can use --no-reboot for secondary environment to eliminate the restart.

*Command:*
```
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
```
**Sample output:**
```
Creating backup for i-03ece495a76794506
Creating AMI with reboot:
ami-070c016792f06fa69
```

**3.Update and reboot the machine. Wait for the node "/testall" endpoint to return "OK".**

This is a sample maintenance activity. Here we are updating and rebooting the machine which has been taken out of LB. Once the instance is up. We need to make sure that the application is up and running. Steps for doing this activity is written inside a function called "updateandreboot ()".Calling the function with argument as instance IP will. perform the following actions.

*Command:*
```
#getting instance IP.
instanceip=($(aws ec2 describe-instances --instance-ids $instance --query Reservations[].Instances[].PublicIpAddress --output=text))
 Note: Replace PublicIpAddress with PrivateIpAddress for private network.

updateandreboot ()
{
  echo "Starting sytem upgrade......"
  ssh -i ~/Downloads/app.pem ec2-user@$1 'sudo /usr/bin/yum update -y; sudo reboot'
  sleep 1m
  echo "Checking application status"
  responce=$(curl -I https://{your_auth0_server}/testall  --write-out %{http_code} --output /dev/null --silent)
  echo "$responce"
  if [[ "$responce" == "200" ]]
  then 
    echo "Application is UP"
  else
    echo "Application is DOWN"
    exit 1
  fi
}
```
An user confirmation is added for continuing the maintenance activity. Skipping the maintenance part makes the script usefull for taking daily backup and cleanup.

*Command:*
```
echo "Do you want to perform a system update?"
echo "Type 'yes'| 'no'"
read continue
if [ $continue = yes ]
then
updateandreboot $instanceip
elif [ $continue = no ]
  then
  echo "No maintenance for $instance"
else
  echo "Enter either 'yes' or 'no'"
fi
```

**Sample output:**
```
Do you want to perform a system update?
Type 'yes'| 'no'
yes
Starting sytem upgrade......
Loaded plugins: amazon-id, rhui-lb, search-disabled-repos
No packages marked for update
Connection to xx.xx.xx.xx closed by remote host.
Checking application status
200
Application is UP
```
If the application is down the script exit saying "Application is down". The you have troubleshoot for the issue on server.

**4.Add the node back to the load balancer.**

Once the maintenance is completed and the application is up. We can add the instance back to LB.

*Command:* 
```
aws elb register-instances-with-load-balancer --load-balancer-name $lb --instances $instance
```
**Sample output:**
```
Adding target back to LB
{
    "Instances": [
        {
            "InstanceId": "i-0c137c56b308ce3c5"
        },
        {
            "InstanceId": "i-03ece495a76794506"
        }
    ]
}
```

Now the maintenance activity is completed for the first instance. Since we are performing it in a loop. The same actions will be carried out for the other instances attached to the LB.

**5.Remove the old backups and AMIs along with the EBS volume snapshots that are no longer needed.**

Once the backup creation and maintenance is completed for all the instances, we can delete the old backup AMI's and snapshot associated with it. The script will ask for an user confirmation for proceeding the deletion proces. If you don't want to delete the backup now, then you can skip the procces by giving "no" as user input.

If the user input is "yes", create an array containing the list of AMI's created by you. We can use the command below creaing the array with AMI's.

*Command:*
```
echo "Do you wish to remove old AMI?"
echo "Type 'yes | no'"
read old
if [ $old == yes ]
then
  echo "Fetching AMI details ...."
ami_array=($(aws ec2 describe-images --owners=488905371868 --query Images[].ImageId --output=text))
```
Now the array is created, we can iterate the elements in the array using a for loop and collect the metadat for the AMI.

*Command:*
```
array_length=${#ami_array[@]}
  for (( i=0; i<$array_length; i++ ))
  do
    image_id=${ami_array[$i]}
    image_name=($(aws ec2 describe-images --image-ids=$image_id  --query Images[].Name --output=text))
    image_date=($(aws ec2 describe-images --image-ids=$image_id  --query Images[].CreationDate --output=text | cut -d'T' -f1))
```
Now we need to compare the AMI creation date and today's date. We will be deleting all the old AMI's other than which created today. "Date" command can be used for this. It today's date is greater than image creation date, script will ask for user confirmation to delete AMI. Before deleting the AMI, it will display the metadata of the AMI and ask for user confirmation to delete it. We can either proceed with deletion with input "yes" or discontinue it with "no". If we are proceeding with the deletion process, then we need to get the snapshot of the AMI and need to delete it as well. 

*Command:*

```
    imgdt=$(gdate -d $image_date +%s)
    current_date=$(date +%Y-%m-%d)
    todate=$(gdate -d $current_date +%s)
    if [[ "$todate" > "$imgdt" ]];
    then
      echo "Following AMI is found : $image_id"
      echo ""Image Name : $image_name""
      echo ""Image CreationDate : $image_date""
      #To get snapshot of the AMI's
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
      echo "Image $image_id is created today"
    fi
   ```
   **Sample output:**
   
   Do you wish to remove old AMI?
Type 'yes | no'
yes
Fetching AMI details ....
Image ami-049464c24a3837822 not older than 30 days
Image ami-070c016792f06fa69 not older than 30 days
Image ami-0a657df774e456ebe not older than 30 days
Image ami-0b699c2bd00c897ec not older than 30 days
Following AMI is found : ami-0b7a0f0c0f9342b1e
Image Name : My
Image CreationDate : 2018-09-13
Following are the snapshots associated with it : snap-0e8e7a4a5dfc3647a
Do you wish to proceed with deletion?. Type 'yes | no'
no

    

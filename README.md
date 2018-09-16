# AWS AMI Backup and Cleanup

The primary goal of the script is to automate the backup procedure for a 3 node HA appliance.
```
Note: Before running the script make sure that you have installed and configured aws-cli on the machine.
Please refer the [link] (https://docs.aws.amazon.com/cli/latest/userguide/installing.html) for setting up the AWS command line interface.
```

**Procedure for taking backup and cleanup:**

1) Remove a node from the load balancer.
2) Create an AMI from the node (with reboot for primary and without reboot for secondary).
3) Update and reboot the machine. Wait for the node "/testall" endpoint to return "OK"
4) Add the node back to the load balancer.
5) Remove the old backups and AMIs along with the EBS volume snapshots that are no longer needed.


Inorder to reduce the disruption to the operation of the appliance, the procedure is performed on the secondary database nodes before the primary database node. The script will ask for a user input to enter the environment name. If it is primary, then the complete actions will be performed on primary nodes and similarly for secondary.

Once the environment is set, next the script asks for the application name. "get_lb.sh" script maps the application name to its corresponding loadbalancer(LB). There is no need of checking into the console for getting the LB name.

**Sample output:**
```
Enter the environment. Type 'primary' if it is a primary region, else type 'secondary'
primary
Enter the app name
app2
Load balancer for app2 is : xxxx
```

**Remove a node from the load balancer.**

We can get the list of instances attached to the Lb using the command "aws elb describe-load-balancers". Create an array which holds the "instance-id" of the instances. For loop ins shell scipt can be used to perform maintenance on each instance one at a time. 
```
*Command:*

aws elb deregister-instances-from-load-balancer --load-balancer-name $lb --instances $instance

**Sample output:**

Removing node x-xxxxxxx from the load balancer.
{
    "Instances": [
        {
            "InstanceId": "xxxxx-xxxx"
        }
    ]
}
```

**Create an AMI from the node (with reboot for primary and without reboot for secondary).**

Next is to create an AMI for the instance which has been removed from the LB now. If this is a node in primary environment, AMI should be created with reboot. By default, Amazon EC2 attempts to shut down and reboot the instance before creating the image. You can use --no-reboot for secondary environment to eliminate the restart.
```
*Command:*

Creating AMI with reboot:
   aws ec2 create-image --instance-id $instance --name "$ami" --description "Automated backup created for $instance"
Creating AMI without reboot
   aws ec2 create-image --no-reboot --instance-id $instance --name "$ami" --description "Automated backup created for $instance"

**Sample output:**

Creating AMI with reboot
{
    "ImageId": "ami-06130e3d6d10520d6"
}
```

**Update and reboot the machine. Wait for the node "/testall" endpoint to return "OK".**

This is a sample maintenance activity. Here we are updating and rebooting the machine which has been taken out of LB. Once the instance is up. We need to make sure that the application is up and running. Steps for doing this activity is written inside a function called "updateandreboot ()".Calling the function with argument as instance IP will. perform the following actions.
```
*Command:*

updateandreboot ()
{
ssh -i ~/Downloads/app.pem ec2-user@$1 "sudo /usr/bin/yum update -y"; "sudo reboot"
sleep 1m
echo "Checking application status"
#if curl -I -H "$instanceip" http://localhost/testall | grep "301 Moved Permanently" > /dev/null;
if ssh -t -t -i ~/Downloads/app.pem ec2-user@$1 "echo SUCCESS; w"; 
then 
	echo "Application is UP"
else
   echo "Application is DOWN"
   exit 1
fi
}

**Sample output:**

Authentication failed.
main.sh: line 44: sudo reboot: command not found
Checking application status
SUCCESS
 12:55:21 up 0 min,  1 user,  load average: 0.53, 0.12, 0.04
USER     TTY      FROM             LOGIN@   IDLE   JCPU   PCPU WHAT
ec2-user pts/0    106.206.21.90    12:55    0.00s  0.01s  0.01s w
Connection to 34.219.94.93 closed.
Application is UP
```
**Add the node back to the load balancer.**

Once the maintenance is completed and the application is up. We can add the instance backup to LB.
```
*Command:* 
aws elb register-instances-with-load-balancer --load-balancer-name $lb --instances $instance

**Sample output:**

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

**Remove the old backups and AMIs along with the EBS volume snapshots that are no longer needed.**

Once the backup creation and maintenance is completed of all the instances, we delete the old backup AMI's and snapshot associated with it. 
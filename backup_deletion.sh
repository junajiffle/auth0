#!/bin/sh

echo "Collecting snapshot information"
# How many days do you wish to retain backups for? Default: 7 days
retention_days="1"
retention_date_in_seconds=`date +%s`
echo "$retention_date_in_seconds"

image_id=($(aws ec2 describe-images  --owners 488905371868  --query Images[*].ImageId  --output=text))
image_length=${#image_id[@]}
for (( i=0; j<$image_length; j++ ))
do
	echo "$image_id"
	snapshot=($(aws ec2 describe-images --image-ids $image_id | grep "SnapshotId" | cut -d: -f2 | sed -e 's/^ "//' -e 's/"$//'))
	echo "$snapshot"
	snap_date=($(aws ec2 describe-images --owners 488905371868 --image $image_id --query Images[].{date:CreationDate} --output=text | awk -F "T" '{printf "%s\n", $1}'))
	snapshot_date=`gdate -d $snap_date +%s`
	echo "$snapshot_date"
	if [[ "$snapshot_date" -gt "$retention_date_in_seconds" ]]; then
		aws ec2 deregister-image --image-id $image_id
		echo "Deleted AMI $image_id"
	    aws ec2 delete-snapshot --snapshot-id $snapshot
	    echo "Deleted snapshot $snapshot"
	 else
	   	echo "No Backup older than $retention_days days found"
	 fi
done



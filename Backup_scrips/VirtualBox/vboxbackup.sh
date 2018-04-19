#!/bin/bash

VMNAME=$1
BACKUPDIR=/vmbackup/backup
STATE=`sudo -uvbox vboxmanage showvminfo $VMNAME | grep State | awk '{ print $2 }'`
source_type="zero"
check_dev=`sudo -uvbox vboxmanage showvminfo $VMNAME | grep UUID | grep IDE | grep -v "iso"`
if [ -z "$check_dev" ]; then
    SOURCE=`sudo -uvbox vboxmanage showvminfo $VMNAME | grep SATA | grep -v "Empty" | grep -v "Storage"  | awk '{ print $5 }'`
    source_type='SATA'
else
    SOURCE=`sudo -uvbox vboxmanage showvminfo $VMNAME | grep IDE | grep -v "Empty" | grep -v "Storage"  | awk '{ print $5 }'`
    source_type='IDE'
fi

exp=`basename $SOURCE | sed "s/[^.]*.//"`

mails=( ENTER_EMAIL_ADDRESS_HERE_SEPARATES_WITH_SPACE )
DAYS=$2

if [ -z "$DAYS" ]; then
	DAYS=1
fi

RED="\e[38;5;196m"
GREEN="\e[38;5;46m"
YELLOW="\e[38;5;226m"
CLEAR="\e[0m"

function debug {
        printf "%-25s %-20s\n" "VM backup name:" "$VMNAME"
        printf "%-25s %-20s\n" "Check backup destenation:" "$BACKUPDIR"
        if ! [ -d $BACKUPDIR/$VMNAME ]; then
                error=`mkdir -p $BACKUPDIR/$VMNAME`
                if [[ "$?" == "0" ]]; then
                        echo -e $GREEN"Create directory seccessuful"$CLEAR
                else
                        echo -e $RED"Create directory failed. Check backup destanetion"$CLEAR
                fi
        fi
        printf "%-25s %-20s\n" "Disk type is:" "$source_type"
        for item in $SOURCE; do
                printf "%-25s %-20s\n" "Disk image:" "`basename $item`"
                files=$item
        done
        printf "%-25s $GREEN%-20s $CLEAR\n" "Check state of VM:" "$STATE"
        echo -e $YELLOW"Semulation backup"
        printf "%-25s $YELLOW%-20s $CLEAR\n" "Copy file:" "$files"
        printf "$YELLOW%-25s $YELLOW%-20s $CLEAR\n" "To Destenation:" "$BACKUPDIR/$VMNAME/$VMNAME-`date +%d.%m.%y`-`basename $files`"
        cp $files $BACKUPDIR/$VMNAME/$VMNAME-`date +%d.%m.%y`-`basename $files`
        if ! [ -f $BACKUPDIR/$VMNAME/$VMNAME-`date +%d.%m.%y`-`basename $files` ]; then
                echo -e $RED"Error, backup filed"$CLEAR
        else
                echo -e $GREEN"Test backup OK"$CLEAR
        fi
        echo -e $GREEN"`ls $BACKUPDIR/$VMNAME && du -sh $BACKUPDIR/$VMNAME/*`"$CLEAR
        echo -e $YELLOW"Cleaning"$CLEAR
        rm -rf $BACKUPDIR/tmp
}

if [ $2 == "debug" ]; then
        echo -e "Debug mode \n"
        debug
        exit 0;
fi

function high_alert_mail {
  vms_list=`ls $BACKUPDIR | grep $VMNAME`
  size=`for vm in ${vms_list[@]}; do du -h $BACKUPDIR/$vm | awk '{ print $1}'; done`
  count=`for vm in ${vms_list[@]}; do ls $BACKUPDIR/$vm | wc -l; done`
  echo -e "VM's Backup: server: `ip -4 a show | grep inet | grep 255 |awk '{ print $2 }'`"
  echo "╔════════════╦═════════╦══════════╗"
  printf "║ %10s ║ %7s ║ %8s ║\n" "VM name" "count" "Size"
  echo "╠════════════╬═════════╬══════════╣"
   for vm in ${vms_list[@]}; do
     size=`du -h $BACKUPDIR/$vm | awk '{ print $1}'`
     count=`ls $BACKUPDIR/$vm | wc -l`
     printf "║ %10s ║ %7s ║ %8s ║\n" "$vm" "$count" "$size"
   done
  echo "╚════════════╩═════════╩══════════╝"
}

echo -e "`date +%d.%m.%y` `date +%H:%M:%S` \t Cheking state of VM host $VMNAME" >> /var/log/backup.log
echo -e "`date +%d.%m.%y` `date +%H:%M:%S` \t State $STATE. Trying to pause" >> /var/log/backup.log
while [[ $STATE == "running" ]]
  do
    sudo -uvbox vboxmanage controlvm $VMNAME savestate
    sleep 30
    STATE=`sudo -uvbox vboxmanage showvminfo $VMNAME | grep State | awk '{ print $2 }'`
done

echo -e "`date +%d.%m.%y` `date +%H:%M:%S` \t $VMNAME is alrady stoped" >> /var/log/backup.log
echo -e "`date +%d.%m.%y` `date +%H:%M:%S` \t Cheking if backup directory is not exist" >> /var/log/backup.log

if ! [ -d $BACKUPDIR/$VMNAME ]; then
    echo -e "`date +%d.%m.%y` `date +%H:%M:%S` \t Backup directory $BACKUPDIR/$VMNAME is not exist, creating" >> /var/log                                               /backup.log
    mkdir -p $BACKUPDIR/$VMNAME
else
    echo -e "`date +%d.%m.%y` `date +%H:%M:%S` \t Backup directory $BACKUPDIR/$VMNAME is exist, continuing" >> /var/log/b                                               ackup.log
fi

for disk in $SOURCE; do
        error="`cp $disk $BACKUPDIR/$VMNAME/$VMNAME-\`date +%d.%m.%y\`-\`basename $disk\``"
        get_error=$?
done

for email in ${mails[@]}; do
  if [[ "$get_error" == "0" ]]; then
    high_alert_mail | mail -s "Optimistks $VMNAME backup is OK" "$email"
    find $BACKUPDIR/$VMNAME/ -type f -mtime +$DAYS -print0 | xargs -0 rm -f
  else
    echo -e "Backup failure with error: $error" | mail -s "Optimistks $VMNAME backup error" "$email"
    echo -e "`date +%d.%m.%y` `date +%H:%M:%S` \t Error code: $get_error" >> /var/log/backup.log
    echo -e "`date +%d.%m.%y` `date +%H:%M:%S` \t Backup error: $error" >> /var/log/backup.log
  fi
done
log=`sudo -uvbox vboxmanage startvm $VMNAME --type headless`
echo -e "`date +%d.%m.%y` `date +%H:%M:%S` \t `echo $log`" >> /var/log/backup.log

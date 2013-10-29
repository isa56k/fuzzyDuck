#!/bin/bash
# 
#       Author: t:@isa56k e:me@isa56k.com w:www.isa56k.com
# 	      File: fuzzyDuck.sh
#      version: 0.3
# 	     About: A shell script that is used to fuzz on an iOS device. 
#               Creates a webserver to serve up test cases that are 
#               created via zzuf and then uses sbopenurl to try and
#               launch the test case. If a crash is found it is saved
#               to crashes directory for further inspection. Quack!!   
# Instructions: 1. Jailbreak iDevice
#               2. Install APT 0.7 Strict from cydia
#               3. Install OpenSSH from Cydia. 
#               4. Close Cydia on device.
#               5. Logon to device and change ssh root password from alpine (type passwd) at prompt!
#				6. Make a directory in /var/root called fuzzyDuck (e.g mkdir /var/root/fuzzyDuck )
#               7. SCP this script to directory on device you just created
#               8. Type chmod +x fuzzyDuck.sh to make executeable
#               9. run (see example)
#      Example: ./fuzzyDuck.sh <filename> <url> <port> <sleep>
#               ./fuzzyDuck.sh fuzzThis.mov http://localhost 3000 15
# Arguments
testFile=$1 # First is the file we are going to fuzz
url=$2 # The root url for the test case
port=$3 # The port to start the webserver and connect to for testing
sleeptime=$4 #Time to sleep between testcases (this should probably be the length of the mov file before it is fuzzed?)
#address=$5 # Address for iMessage crash if found (Not used at present).

# Directories
testCaseDir=./01_testcases/
crashDir=./02_crashes/
logDir=./03_logs/
configDir=./04_conf/
CrashReporter=/private/var/mobile/Library/Logs/CrashReporter/
PanicLogsCrashReporter=/var/logs/CrashReporter/Panics # Directory that stores kernel panics
varLogsCrashReporter=/var/logs/CrashReporter/

# Config Files
lighttpdConf=./04_conf/fuzzyDuck.conf # Contains lighttpd configuration 
lastTestCaseDat=./04_conf/lastTestCase.dat # File that holds the last test case, used if device reboots or kernel panic
lastSeedUsedDat=./04_conf/lastSeedUsed.dat # File that holds the last test seed used.
lastRatioUsedDat=./04_conf/lastRatioUsed.dat # File that holds the last test ratio used.
kernelPanicStatusDat=./04_conf/kernelPanic.dat # Status if recovering from kernel panic
iMessageAddressDat=./04_conf/iMessage.dat # Address for iMessage to send too

# upD0g Stuff
upD0g="/bin/bash $(readlink -f $0) $1 $2 $3 $4"
upD0gFile="$configDir"upD0g.sh
upD0gDaemon=./04_conf/com.56klabs.upD0g.xml

# Other variables
fuzzedfile="fuzzed_$1" # This is the output file that has been fuzzed that we will eventually test
counter=1 # Counter for working out the test case that has failed

# Have to check the logs directory situation as this won't work if the logs dir isn't in place
if [ -d 03_logs ] 
	then
		LOGFILE="$logDir`date +%Y-%m-%d-%H%M%S`.log" # Logilfe to use
	else
		LOGFILE="intialsetup.log" # Logilfe to use
fi

# Function to log to screen and logfile
log(){
    message="$@"
    echo $message
    echo $message >> "$LOGFILE"
}

# Function to check required executeables are installed
installed(){

	#Application passed into funtion to check 
	application="$@"

	# Check if it exists
	if command -v $application >/dev/null ;then
	   #if it does return 0
	   return 0
	else
	   #if it doesn't return 1
	   return 1
	fi
}

# Install software
installSoftware()
{
	# Get the passed in variables into names that I recognise
	application=$1 # The application e.g. wget / sbopenurl
	installType=$2 # Either via wget or apt-get
	package=$3 # package to install e.g. awk, com.innoying.sbutils, zzuf_0.13-1_iphoneos-arm.deb 
	installURL=$4 # URL to get the app from when using wget

	# Call the install function to see if the application exisits
	if installed $1; 
  		then 
  			# If it does exist log to the user we found it
  			log "[i]: Found $application installed :)"
  		else
  			if [ ! -z "$PS1" ]; then
				# Get user input to start fuzzing
				log "[i]: Software install must be run interactively, exiting."
				exit
			fi
  			# Ask user if they want to install
  			log "[i]: Would you like to install $application?"
	  		# yes / no / cancel select statement to prompt user
	  		select result in Yes No Exit
			do
				# First case statement to check user input yes / no / cancel
		    	case $result in
		    		# if yes
		        	"Yes")
						# Log to user we are installing
						log "[i]: Installing $application..."
						# 2nd case statement to check install method
						case $installType in
							# if it is apt-get install then use apt-get
							"apt")
								apt-get -y --force-yes install $package 2> /dev/null
								break
								;;
							# if it is get then use wget to download and install with dpkg
							"get")
								wget -q --no-check-certificate $installURL
								dpkg -i $package 2> /dev/null
								break
								;;
						esac
		            	break
		            	;;
		            # if user selects no then log
		        	"No")
		            	log "[e]: You brave or stupid, oh well your choice!"
						break
		            	;;
		            # If user selects exit then log and quit the application
		        	"Exit")
		            	log "[i] Now exiting. Come back soon, we need you to fuzz. ;( "
		            	cleanUp
						exit
		            	;;
		            # Catch any nvalid options
		        	*) echo invalid option;;
		    	esac
			done
 	fi
}

# Funtion to create required directories
makingDirs(){
	if [ -d $1 ]
	then 
		log "[i]: Found direcotry $1."
	else 
		log "[w]: Direcotry $1 not found, creating."
		mkdir $1
fi
}

# Cleanup function from ctrl+c
cleanup(){
  
  # Kill lighttpd
  killall -9 lighttpd 2> /dev/null

  # Set the kernel panic value to 0 as clean exit
  echo 0 > $kernelPanicStatusDat
  
  return $?
}

# Function to trap control+c
control_c()
# run if user hits control-c
{
  echo -en "\~~~: Ouch! Now Exiting :~~~\n"
  cleanup
  exit $?
}

# When user calls ./fuzzyDuck.sh cleanmeup then all the directories are deleted
resetFuzzyDuck(){
	log "[w]: Reseting fuzzyDuck and deleting all driectories. Bye."
	# Was going to do rm -r 0* but deviced to be a bit more cautious
	rm -r $testCaseDir 2> /dev/null 
	rm -r $crashDir 2> /dev/null 
	rm -r $logDir 2> /dev/null 
	rm -r $configDir 2> /dev/null 
	# Quit and let user start again
	exit
}

# Fucntion called after 1st run from kernelPanic to find crash logs
findCrashLogs()
{
	# $1 = Directory where the crashes might be found
	# $2 = The output directory to store crashes for inspection
	# $3 = The counter for the test case so can match them all up

	# set a log counter
 	logCounter=0

 	# Get the last test case
 	if [ -e $lastTestCaseDat ]; then 
 		lastTestCase=$(<$lastTestCaseDat); 
 	else 
 		log "[e]: Unable to find $lastTestCaseDat"
 		cleanup
 		exit
 	fi

 	# Get the last seed
 	if [ -e $lastSeedUsedDat ]; then 
 		lastSeedUsed=$(<$lastSeedUsedDat); 
 	else 
 		log "[e]: Unable to find $lastSeedUsedDat"
 		cleanup
 		exit
 	fi

 	#Get the last ratio
 	if [ -e $lastRatioUsedDat ]; then 
 		lastRatioUsed=$(<$lastRatioUsedDat); 
 	else 
 		log "[e]: Unable to find $lastRatioUsedDat"
 		cleanup
 		exit
 	fi

		# Search for the crash logs
		find $1 -type f | while read line 
		do
			# Increment counter
			(( logCounter++ ))

			# Tell the user that the crash log has been found
			log "[i]: Found following crash $line"

			# The Test case and see were
			log "[i]: Test case used was $lastTestCase with seed $lastSeedUsed and ratio $lastRatioUsed."
			
			# Tell the user it will be moved to the crashes directory
			log "[i]: Moving crash $line to directory $2"
		
			# Move the crash to the crash directory
			mv $line $2/"$3"_$(basename $line) 2> /dev/null
			
			# If there is no test case for the crash create it
			if [ ! -e $2/$(basename $lastTestCase) ]; then

				# Tell user moving last test case to the crash directory	
				log "[i]: Moving test case $lastTestCase to directory $2/"

				# If a test case exists then move it if not then error to the user
				if [ -e $lastTestCase ]; then

					# Now move the test case that caused the panic to the directory
					mv $lastTestCase $2

					# Log to user that it has been moved
					log "[i]: Moved the test case $lastTestCase to $2/"

				# Error that test case couldn't be found
				else
					# Log the error
					log "[e]: Unable to find $lastTestCase, something is not right here?"
				
				# end if
				fi

				# Let user know that we saving seed info
				log "[i]: Creating seed info for $line in $2/$(basename $lastTestCase).info"

				# Create the seed info
				echo "Seed Used = $lastSeedUsed" > $2/"$(basename $lastTestCase)".info

				# Let user know we are saving ratio info
				log "[i]: Creating ratio info for $line in $2/$(basename $lastTestCase).info"

				# Create the ratio info
				echo "Ratio Used = $lastRatioUsed" >> $2/"$(basename $lastTestCase)".info
			# end if
			fi 

		# All done :)
		done

}

# Hidden(ish) feature :)
iMessage()
{
	# Used to send iMessage but you need to install biteSMS (licensed) 
	# & configure 04_conf/iMessage.dat with your address.
	if [ -e /Applications/biteSMS.app/biteSMS ]; then	
		if [ -e $iMessageAddressDat ]; then 
			iMessageAddress=$(<$iMessageAddressDat); 
			echo iMessageAddress
			/Applications/biteSMS.app/biteSMS -send -iMessage $iMessageAddress 
			log "[i]: iMessage $1 sent to $iMessageAddress."
		fi
	fi
}
 
# trap keyboard interrupt (control-c)
trap control_c SIGINT

# Echo startup
log "[i]: Starting ${BASH_SOURCE[0]} @ `date`"

# Check if runnign interactively or as a daemon
if [ -z "$PS1" ]; then
	# Let user know in interactive mode
	log "[i]: You are running in interactive mode!"
else
	# or in daemon mode
	log "[i]: You are running as a daemon!"
fi

# Check that fuzzyDuck.sh isn;t already running
status=`ps -efww | grep -w "fuzzyDuck.sh" | grep -v grep | grep -v $$ | awk '{ print $2 }'`

# Exit if it is running 
if [ ! -z "$status" ]; then
       log "[e]: fuzzyDuck.sh process is already running. Kill it and try again!! "
        exit 1;
fi

# Check for required software apt-get, lighttpd, zzuf, sbopenurl and install if not there
log "[i]: Checking for required software."

# Check if apt is installed and exit if it's not as cant go any further
if installed 'apt-get'; 
  then 
  	log "[i]: Found apt-get installed :)"
  else
  	log "[E]: You need to install APT 0.7 Strict from cydia. Install and re-run script"
  	cleanup
  	exit 1
fi

# Check and install wget
installSoftware wget apt wget

# Check and install gawk
installSoftware awk apt gawk

# Check and install sbopenurl
installSoftware sbopenurl apt com.innoying.sbutils

# Check and install plutil
installSoftware plutil apt com.ericasadun.utilities

# Check and install lighttpd
installSoftware lighttpd apt lighttpd

# Check and install zuff
installSoftware zzuf get zzuf_0.13-1_iphoneos-arm.deb https://dl.dropboxusercontent.com/u/19521614/zzuf_0.13-1_iphoneos-arm.deb 

# Clean up the directories as cleanup specified
if [ "$1" = cleanUp ]; then 	
	# Call to resetFuzzyDuck function
	resetFuzzyDuck 
fi

# Install upD0g launchDaemon
if [ "$1" = installUpD0g ]; then 	
	# Check if the plist file exists to install 
	if [ ! -f $configDir$upD0gDaemon ]; then
		# At this point the conf directory might not exist so lets create it if needed
		makingDirs 04_conf
		# Log didn't find launchDaemon downloading
		log "[i]: Didn't find upD0g launchDaemon to install, downloading."
		# Grab the plist file
		wget -q --no-check-certificate https://dl.dropboxusercontent.com/u/19521614/com.56klabs.upD0g.xml -O $upD0gDaemon
		# The xml file doesn;t know where fuzzyDuck.sh is so need to add it in
		sed -i -e 's?InsertRootHere?'`pwd`?'g' $upD0gDaemon
		# This is to work out the workingDir
		sed -i -e 's?TheWorkingDir?'`pwd`?'g' $upD0gDaemon
		# Now convert to binary plist file
		plutil -convert binary1 $upD0gDaemon 2> /dev/null
	fi 
	 # Tell user we are installing the upD0g Daemon
	log "[i]: Installing upD0g launchDaemon."
	sleep 2 # Stupid ass sleeps to give a bit of flow control and humour
	# No need for this...
	log "[j]: What's upD0g?"
	sleep 3 # Stupid ass sleeps to give a bit of flow control and humour
	# Really no need..
	log "[j]: Nuttin dawg.... whats up wit you?"
	sleep 4 # Stupid ass sleeps to give a bit of flow control and humour
	# So this is what upD0g is =)
	log "[i]: upD0g is a launchDaemon designed to run at boot time, this helps with automated testing after a kernel panic."
	# Copy the plist to /System/Library/LaunchDaemons
	mv $upD0gDaemon /System/Library/LaunchDaemons/com.56klabs.upD0g.plist
	# Laod the daemon
	launchctl load -w /System/Library/LaunchDaemons/com.56klabs.upD0g.plist 2> /dev/null
	# log to user upD0g is now installed 
	log "[i]: upD0g is now installed. To remove use ./fuzzyDuck.sh removeUpD0g"
	# Exit
	cleanup
	exit
fi

# remove upD0g launchDaemon
if [ "$1" = removeUpD0g ]; then 	
	# Just...
	log "[i]: What's upD0g?"
	sleep 2 # Stupid ass sleeps to give a bit of flow control and humour
	# because...
	log "[i]: I'm outta here, a dawg gotta do what a dawg gotta do... ltrz."
	sleep 3 # Stupid ass sleeps to give a bit of flow control and humour
	# Unload the launchDaemon
	launchctl unload -w com.56klabs.upD0g 2> /dev/null 
	# And delete it
	rm /System/Library/LaunchDaemons/com.56klabs.upD0g.plist 2> /dev/null
	# Log to user its gone
	log "[i]: upD0g has been removed, fuzzyDuck will not run after a reboot."
	# log to user upD0g is now removed
	log "[i]: To install again use ./fuzzyDuck.sh installUpD0g."
	# Exit
	cleanup
	exit
fi

# Check for the arguments submitted and error if none
if [ $# -ne 4 ]; then
	# Log the wrong args supplied 
    log "[e]: Wrong arguments supplied. (Usage example: ./fuzzyDuck.sh fuzzThis.mov http://localhost 3000 15)" 
    # and exit
    cleanup
    exit 1 
fi

# If the Mov file doesn't exist dump out
if [ ! -f $1 ]; then
	# Log it and 
	log "[e]: Can't find $1, exiting."
	# exit out
	cleanup
	exit
fi  

# Check for required directories and create if they don' exist
log "[i]: Checking for required directories."
# Call the function makingDirs and pass in name of directory to create
makingDirs $testCaseDir 
makingDirs $crashDir
makingDirs $logDir
makingDirs $configDir

# Now we have a proper logs directory we can move the log to the directory and continue using that
if [ -e intialsetup.log ] 
	then
		log "[w]: Moving initalsetup.log to logs dir and renaming"
		LOGFILE="$logDir`date +%Y-%m-%d-%H%M%S`.log" 
		mv intialsetup.log $LOGFILE
		log "[i]: Using log file $LOGFILE."
	else
		log "[i]: Using log file $LOGFILE."
fi

# Create a directory specifically related to this fuzzing session
sessionDate="`date +%Y-%m-%d-%H%M%S`" # Get the date and time this session started 
log "[i]: Using session date of $sessionDate"

# create a variable to hold testcasedir
sessionTestCaseDir="$testCaseDir$sessionDate"

# make the test cases dir
makingDirs $sessionTestCaseDir # Then create a testcases directory for the session

# create a variable to hold crashdir
sessionCrashDir="$crashDir$sessionDate"

# Make the session crash dir
makingDirs $sessionCrashDir 

# Make the panic dir for kernel panics
makingDirs $sessionCrashDir/panics

log "[i]: Session directories created ($sessionTestCaseDir and $sessionCrashDir)"

# Web Server Setup
# Let user know will be killing off any lighttpd processes
log "[w]: Killing off any old lighttpd processes."

# Kill of any old lighttpd processes
killall -9 lighttpd 2> /dev/null

# Let user know we are going to chec for lighttpd configuration file
log "[i]: Checking for lighttpd configuration file fuzzyDuck.conf."

#if fuzzyDuck.conf doesn't exist 
if [ -f $lighttpdConf ];
	then
		# Let user know we have the config file for lighttpd
		log "[i]: lighttpd config file $lighttpdConf exists."
	else
		# Log that we are downloading the config file
		log "[w]: Downloading fuzzyDuck.conf file for lighttpd configuratiom."
		
		# download it
		wget -q --no-check-certificate https://dl.dropboxusercontent.com/u/19521614/fuzzyDuck.conf -O $lighttpdConf

		# Need to update fuzzyDuck.conf with the directory we are running in
		sed -i -e 's?InsertRootHere?'`pwd`?'g' $lighttpdConf
fi

#Let user know we are going to start lighttpd
log "[i]: Starting lighttpd web server."

# Start the lightttpd
lighttpd -f $lighttpdConf 2> /dev/null 

#Let user know we are going to kill of any old Safari processes
log "[w]: Killing off any old MobileSafari processes."

# Kill off any Safari sessions that might be lingering:
killall -9 MobileSafari 2> /dev/null
#
# Before we start fuzzing we need to check if we are recovering from a kernel panic
# and save the last run test case and crash dump move them to the crash dir
#
# If the kernel panic file that we create when running a test case exists then 
# we should check for crashes. If it doesn't exist then the chances are the device 
# rebooted or restarted woth out a kernel panic.
# 
if [ -e $kernelPanicStatusDat ]; then 
	# Pull kernel panic value fro file into a variable
	kernelPanic=$(<$kernelPanicStatusDat); 
	log "[i]: Kernel Panic value is <$kernelPanic>."
fi

if [[ kernelPanic -eq 1 ]]; then
	# Log to the user we think there has been kernel panic caused by a 1 in kernelpanic.dat
	log "[i]: Looks like you are recovering from a kernel panic."

	# Send iMessage
	iMessage KernelPanicRecovery

	# Get the test case that caused the panic
	lastTestCase=$(<$lastTestCaseDat)

	# Log to the user the test case that has caused the panic
	log "[i]: The last test case to run was $lastTestCase"

	# Work out the last session crashes dir you should be moving to
	lastCrashDir=$(echo $lastTestCase | awk -F / '{ print $3 }')

	# Need to work out the counter that was used in the last test case
	tmp="${lastTestCase##*/}"

	# Extract it from the filename
	lastCounter="${tmp%%_*}"

	# Tell user the last directory used to store crashes on last test run
	log "[i]: The last crash directory used was $lastCrashDir."

	# Search the /var/logs/CrashReporter directory
	findCrashLogs $varLogsCrashReporter $crashDir$lastCrashDir/panics $lastCounter

	# Log to the user that all crashes and the test case have been moved to the directory
	log "[i]: All crash dumps and logs have been recovered to the direcotry $crashDir/$lastCrashDir."

	# Set the kernel panic back to 0 incase script is killed off and run again
	echo 0 > $kernelPanicStatusDat
fi
#

# Writing to upD0g for restart and laucnhDaemon
echo "#!/bin/bash" > $upD0gFile

# Add a sleep of 5 mins so that the script doesn;t start up straight away and get stuck in a shitty loop
echo "sleep 300" >> $upD0gFile

# Echo the command we ran these test cases with
echo $upD0g >> $upD0gFile

# Set permissions on upD0g
chmod +x $upD0gFile

# Let user know whats upD0g.
log "[i]: Written restart command to upD0g."
sleep 1
log "[j]: What's upD0g? [ ./fuzzyDuck.sh installUpD0g || ./fuzzyDuck.sh removeUpD0g ] "

if [ -z "$PS1" ]; then
	# If we are running interactive then lets test the original test case to check that it will actually launch
	log "[i]: Would you like to play your test case to check it plays on your device before it is fuzzed?"
	select result in Yes No
	do
		# First case statement to check user input yes / no / cancel
    	case $result in
    		# if yes
        	"Yes")
				# Logging to user that we are going to play the test case
				log "[i]: Now launching your original test case before it is fuzzed."
				# Copy test case to the root directory for lighttpd
				cp $1 . 2> /dev/null
				# Launch the test case un-fuzzed
				sbopenurl $url:$port/$1
				# Log to the user and ask if the test case played
				log "[i]: Did the test case play ok (ctrl+c to exit and fix if not) ?"
            	break
            	;;
            # if user selects no then log
        	"No")
            	log "[i]: Not testing original test case."
				break
            	;;
            # Catch any invalid options
        	*) echo invalid option;;
    	esac
	done

	# Get user input to start fuzzing
	read -p "[i]: Hit [Enter] key to begin fuzzytime (ctrl+c to quit)."
fi
log "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
#
# Main fuzzing part, a loop to create test cases and then test them
# if a crash is found they are copied into their own directory with
# the test case to save for later inspection and testing.
#
while :
do
	# Let the user know we are starting the test 
	log "[i]: Test case $counter for $testFile starting @ `date`"
	
	# Set the $testcase variable
	testCase="$counter"_"$fuzzedfile"
	
	# Get $RANDOM into a variable so we can use and log later
	seed=$RANDOM

	# Put seed into seed .dat file
	echo $seed  > $lastSeedUsedDat

	# Set ratio value in a variable so we can record it later 
	ratio="0.0001:0.001"

	# Put seed into seed .dat file
	echo $ratio  > $lastRatioUsedDat

	# Let the user know we creating the test case
	log "[i]: Creating test case $testCase using seed $seed and ratio $ratio"

	# Used to calculate the time to create the test case
	T="$(date +%s)" 

	#zzuf to create a test case taking an input file and then outputs file. -s uses random to get a random seed and -r is the ratio. 
	zzuf -s $seed -r $ratio < $testFile > $sessionTestCaseDir/$testCase

	# Used to calculate the time to create the test case
	T="$(($(date +%s)-T))"
	
	# Echo the time it took to create the test case
	log "[i]: Time to create the test case in seconds: $T"
	
	# Echo the name of test case created
	log "[i]: Test case $sessionTestCaseDir/$testCase created with seed $seed and ratio $ratio"
	
	# Update the last test case log file so that if it kernel panics we can get the crash and crash log
	echo "$sessionTestCaseDir/$testCase" > $lastTestCaseDat

	# Let user know we captured the last test case detailds
	log "[i]: Recorded testcase details ($sessionTestCaseDir/$testCase)for future refernece."
	
	# Update kernelPanic.dat
	echo "1" > $kernelPanicStatusDat

	# Let user know kernelpanic.dat has been updated
	log "[i]: Updated $kernelPanicStatusDat with 1."

	# Let use know we are going to test using the specified URL
	log "[i]: Now testing $url:$port${sessionTestCaseDir:1}/$testCase with Mobile Safari."

	# Use sbopenurl from comex to open safari and launch test case
	sbopenurl "$url:$port${sessionTestCaseDir:1}/$testCase" 

	# Let the user know going to sleep for x second
	log "[i]: Now sleeping for $sleeptime seconds to allow testcase to play / run and crashdump to be created."
	
	# Now sleep, this should probably be the length of the mov file before it is fuzzed?
	sleep $sleeptime

	# Check the crash reporter directory for a crash
	findCrashLogs $CrashReporter $sessionCrashDir $counter

	# Also check the directory /var/log/CrashReporter, some get created here too.
	findCrashLogs $varLogsCrashReporter $sessionCrashDir/panics $counter

	#Let user know we deleted test case
	log "[i]: Set kernelpanic.dat value to 0."

	# Set kernel panic back to 0
	echo "0" > $kernelPanicStatusDat

	# Kill off any Mobile Safari executeables that maybe running and send errors to /dev/null as we don't care about them.
	killall -9 MobileSafari 2> /dev/null

	# Let user know they were killed
	log "[i]: Killed Mobile Safari process."

	# Echo some debug to let user know test case finished
	log "[i]: Test case $counter for $testFile finished."

	# Increment counter for testcase number
	(( counter++ ))

	# Some spacing to make each test case more visible in the log / screen output
	log "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

done

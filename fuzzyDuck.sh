#!/bin/bash
# 
#       Author: @isa56k
# 	      File: fuzzyDuck.sh
#      version: 0.1
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
#				6. Make a directory called fuzzyDuck
#               6. SCP this script to directory on device you just created
#               7. Type chmod +x fuzzyDuck.sh to make executeable
#               8. run (see example)
#      Example: ./fuzzyDuck.sh <filename> <url> <port> <sleep>
#               ./fuzzyDuck.sh fuzzThis.mov http://localhost 3000 15
# Arguments
testfile=$1 # First is the file we are going to fuzz
url=$2 # The root url for the test case
port=$3 # The port to start the webserver and connect to for testing
sleeptime=$4 #Time to sleep between testcases
#address=$5 # Address for iMessage crash if found (Not used at present)

# Other variables
debugmode=1 #Just used this to stop at a few points an debug slowly rather than a crazy loop you can't track
fuzzedfile="fuzzed_$1" # This is the output file that has been fuzzed that we will eventually test
counter=0 # Counter for working out the test case that has failed
filename=/private/var/mobile/Library/Logs/CrashReporter/LatestCrash.plist #Filename for crash reports
LOGFILE="`date +%Y%m%d%H%M%S`.log" # Logilfe to use

# Function to log to screen and logfile
log(){
    message="$@"
    echo $message
    echo $message >>$LOGFILE
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

# Cl		eanup function from ctrl+c
cleanup()
# example cleanup function
{
  killall -9 lighttpd 2> /dev/null
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
 
# trap keyboard interrupt (control-c)
trap control_c SIGINT

# Echo startup
log "[i]: Starting ${BASH_SOURCE[0]} @ `date`"

# Kill off any Safari sessions that might be lingering:
killall -9 MobileSafari 2> /dev/null
log "[w]: Killing off any old MobileSafari processes"

# Check for the arguments submitted and error if none
if [ $# -ne 4 ]
  then
    log "[e]: Wrong arguments supplied. (Usage example: ./fuzzyDuck.sh fuzzThis.m4v http://localhost 3000 6)" 
    exit 1 
fi

# Check for required software apt-get, lighttpd, zzuf, sbopenurl and install if not there
#
# Check if apt is installed and exit if it's not as cant go any further
if installed 'apt-get'; 
  then 
  	log "[i]: Found apt-get installed :)"
  else
  	log "[E]: You need to install APT 0.7 Strict from cydia. Install and re-run script"
  	exit 1
fi

# Check if zzuf is installed
if installed wget; 
  then 
  	log "[i]: Found wget installed :)"
  else
  	log "[i]: Would you like to install wget?"
  	select result in Yes No Exit
	do
	    case $result in
	        "Yes")
				log "[i]: Installing wget..."
				apt-get -y --force-yes install wget
	            break
	            ;;
	        "No")
	            log "[dafuq]: You brave or stupid, oh well your choice!"
				break
	            ;;
	        "Exit")
	            log "[i] Now exiting. Come back soon, we need you to fuzz. ;( "
				exit
	            ;;
	        *) echo invalid option;;
	    esac
	done
 fi

# Check if sbopenurl is installed
if installed sbopenurl; 
  then 
  	log "[i]: Found sbopenurl installed :)"
  else
  	log "[i]: Would you like to install sbopenurl (sbutils) ?"
  	select result in Yes No Exit
	do
	    case $result in
	        "Yes")
				log "[i]: Installing sbopenurl..."
				apt-get -y --force-yes install com.innoying.sbutils
	            break
	            ;;
	        "No")
	            log "[dafuq]: You brave or stupid, oh well your choice!"
				break
	            ;;
	        "Exit")
	            log "[i] Now exiting. Come back soon, we need you to fuzz. ;( "
			    exit
	            ;;
	        *) echo invalid option;;
	    esac
	done
 fi

# Check if sbopenurl is installed
if installed lighttpd; 
  then 
  	log "[i]: Found lighttpd installed :)"
  else
  	log "[i]: Would you like to install lighttpd?"
  	select result in Yes No Exit
	do
	    case $result in
	        "Yes")
				log "[i]: Installing lighttpd..."
				apt-get -y --force-yes install lighttpd
	            break
	            ;;
	        "No")
	            log "[dafuq]: You brave or stupid, oh well your choice!"
				break
	            ;;
	        "Exit")
	            log "[i] Now exiting. Come back soon, we need you to fuzz. ;( "
			    exit
	            ;;
	        *) echo invalid option;;
	    esac
	done
 fi

# Check if zzuf is installed
if installed zzuf; 
  then 
  	log "[i]: Found zzuf installed :)"
  else
  	log "[i]: Would you like to install zzuff?"
  	select result in Yes No Exit
	do
	    case $result in
	        "Yes")
				log "[i]: Installing zzuf..."
				wget -q --no-check-certificate https://dl.dropboxusercontent.com/u/19521614/zzuf_0.13-1_iphoneos-arm.deb 
				dpkg -i zzuf_0.13-1_iphoneos-arm.deb 
	            break
	            ;;
	        "No")
	            log "[dafuq]: You brave or stupid, oh well your choice!"
				break
	            ;;
	        "Exit")
	            log "[i] Now exiting. Come back soon, we need you to fuzz. ;( "
			    exit
	            ;;
	        *) echo invalid option;;
	    esac
	done
 fi

# Check for file to fuzz, if it exists continue, if not exit
if [ -f $testfile ] 
	then 
		log "[i]: Found  $testfile, this will be used."
	else
		log "[e]: Couldn't find $testfile that you specified, exiting."
		exit 1
fi

# Check for testcases directory & create if it doesn't exisit
if [ -d 01_testcases ]
	then 
		log "[i]: Found direcotry 01_testcases."
	else 
		log "[w]: Direcotry 01_testcases not found, creating."
		mkdir 01_testcases 
fi

# Check for the crashes directory & create if does not exist
if [ -d 02_crashes ]
	then 
		log "[i]: Found direcotry 02_crashes."
	else 
		log "[w]: Direcotry 02_crashes not found, creating."
		mkdir 02_crashes 
fi

# Create a directory specifically related to this fuzzing session
sessiondate="`date +%Y%m%d%H%M%S`" # Get the date and time this session started 
log "[i]: Using session date of $sessiondate"

# create a variable to hold testcasedir
testcasedir="01_testcases/$sessiondate"

# make the test cases dir
mkdir $testcasedir # Then create a testcases directory for the session

# create a variable to hold crashdir
crashdir="02_crashes/$sessiondate"

#Make the crash dir
mkdir $crashdir 

log "[i]: Session diretcories created."

# Let user know will be killing off any lighttpd processes
log "[w]: Killing off any old lighttpd processes"

# Kill of any old lighttpd processes
killall -9 lighttpd 2> /dev/null

# Let user know we are going to chec for lighttpd configuration file
log "[i]: Checking for lighttpd configuration file fuzzyDuck.conf"

#if fuzzyDuck.conf doesn't exist 
if [ -f fuzzyDuck.conf ];
	then
		# Let user know we have the config file for lighttpd
		log "[i]: lighttpd config file fuzzyDuck.conf exists"
	else
		# Log that we are downloading the config file
		log "[w]: Downloading fuzzyDuck.conf file for lighttpd configuratiom"
		
		#download it
		wget -q --no-check-certificate https://dl.dropboxusercontent.com/u/19521614/fuzzyDuck.conf
fi

# Start the lightttpd
log "[i]: Starghting lighttpd web server"
lighttpd -f fuzzyDuck.conf 2> /dev/null 

# A loop to create test cases and then test them
while :
do
	# Let the user know we are starting the test 
	log "[i]: Test case $counter for $testfile starting @ `date`"
	
	# Set the $testcase variable
	testcase="$counter"_"$fuzzedfile"
	
	# Let the user know we creating the test case
	log "[i]: Creating test case $testcase"
	
	# Get $RANDOM into a variable so we can use and log later
	seed=$RANDOM

	# Used to calculate the time to create the test case
	T="$(date +%s)" 

	#zzuf to create a test case taking an input file and then outputs file. -s uses random to get a random seed and -r is the ratio. store cmd for later. 
	zzuf -s $seed -r 0.0001:0.001 < $testfile > $testcasedir/$testcase

	# Used to calculate the time to create the test case
	T="$(($(date +%s)-T))"
	
	# Echo the time it took to create the test case
	log "[i]: Time to create the test case in seconds: $T"
	
	# Echo the name of test case created
	log "[i]: Test case $testcase created."

	# Let use know we are going to test using the specified URL
	log "[i]: Now testing $url:$port/01_testcases/$sessiondate/$testcase with Mobile Safari."

	# Use sbopenurl from comex to open safari and launch test case
	sbopenurl "$url:$port/01_testcases/$sessiondate/$testcase" 

	# Let the user know going to sleep for x second
	log "[i]: Now sleeping for $sleeptime seconds to allow crashdump to be created."
	
	# Now sleep 
	sleep $sleeptime

	# if the crash dump occured we need to record it and take a copy for further investogation
	if [ -f $filename ] 
		then 
			# Echo we found a crash and are going to copy it to crashdir
			log -e '\E[1;33;44m' "[i]: Crash found, copying to 02_crashes/$sessiondate/$testcase.plist"; tput sgr0 
			log -e '\E[1;33;44m' "[i]: Seed = $seed "; tput sgr0

			# Cat it's output into a crashes directory
			cat $filename > $crashdir/$testcase.plist 2> /dev/null
			
			# Tell user we are copying the test case so we can reproduce
			log "[i]: Copying test case ($testcasedir/$testcase) to crash directory $sessiondate for further investigation."
			
			# and then copy the test case to the crashes directory
			cp $testcasedir/$testcase $crashdir/$testcase

			# Clean up and delete the crash file
			rm $filename 2> /dev/null
			
			# Tell user we deleted the crash file
			log "[i]: Deleted $filename."

			# Could probably put something in here to send an iMessage or email or something to tell the user about the crash?
	
	fi 

	# Kill off any Mobile Safari executeables that maybe running and send errors to /dev/null as we don't care about them.
	killall -9 MobileSafari 2> /dev/null

	# Let user know they were killed
	log "[i]: Killed Mobile Safari process."

	# Echo some debug to let user know test case finished
	log "[i]: Test case $counter for $testfile finished."

	# Increment counter for testcase number
	(( counter++ ))

	# Some spacing to make each test case more visible in th elog / screen output
	log "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

done



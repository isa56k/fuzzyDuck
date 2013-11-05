fuzzyDuck
=========

      Author: t:@isa56k e:me@isa56k.com w:www.isa56k.com

        File: fuzzyDuck.sh

     version: 0.4

       About: A shell script that is used to fuzz on an iOS device. 
              Creates a webserver to serve up test cases that are 
              created via zzuf and then uses sbopenurl to try and
              launch the test case. If a crash is found it is saved
              to crashes directory for further inspection. Quack!!   

Instructions: 1. Jailbreak iDevice
              2. Install APT 0.7 Strict from cydia
              3. Install OpenSSH from Cydia. 
              4. Close Cydia on device.
              5. Logon to device and change ssh root password from alpine (type passwd) at prompt!
              6. Make a directory in /var/root called fuzzyDuck (e.g mkdir /var/root/fuzzyDuck )
              7. SCP this script to directory on device you just created
              8. Type chmod +x fuzzyDuck.sh to make executeable
              9. run (see example)

     Usage:   ./fuzzyDuck.sh <filename> <url> <port> <sleep>
              ./fuzzyDuck.sh fuzzThis.mov http://localhost 3000 15  <- Standard Usage
              ./fuzzyDuck cleanUp                                   <- Deletes all directories
              ./fuzzyDuck installUpD0g                              <- Installs upD0g launch Daemon to run after reboot / panic
              ./fuzzyDuck removeUpD0g                               <- Removes upD0g launch Daemon

              I also tired to get it to send you an iMessage on finding a crash log but havent got it working yet.
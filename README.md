fuzzyDuck
=========

       Author: @isa56k
         File: fuzzyDuck.sh
      version: 0.1
        About: A shell script that is used to fuzz on an iOS device. 
               Creates a webserver to serve up test cases that are 
               created via zzuf and then uses sbopenurl to try and
               launch the test case. If a crash is found it is saved
               to crashes directory for further inspection. Quack!!   
       How to: 1. Jailbreak iDevice
               2. Install APT 0.7 Strict from cydia
               3. Install OpenSSH from Cydia. 
               4. Close Cydia on device.
               5. Logon to device and change ssh root password from alpine (type passwd) at prompt!	
               6. Make a directory called fuzzyDuck
               7. SCP this script to directory on device you just created
               8. Type chmod +x fuzzyDuck.sh to make executeable
               9. run (see example)
      Example: ./fuzzyDuck.sh <filename> <url> <port> <sleep>
               ./fuzzyDuck.sh fuzzThis.mov http://localhost 3000 15
        
      A lot of this is based on the examples in the iOS hackers handbook and from what I have learned 
      in OpenJailbreak IRC and class.

# Scale-MII

### Scalable MII(Media Independent Interface) IF IP
  
7/17  
XGMII[64bit], GMII[8bit], MII[4bit] supported.  


7/18  
For SPIN support, fixed sequence send_mii and recv_mii.  


7/22  
Add data address header, and fixed each seqence.  


7/23  
Fixed send/recv sequence. Data size is scaled from the header.  


10/6  
RGMII[4bit] supported.  
Add 25GMII[64bit] mode.  


11/5  
RGMII mode Removed.  
RGMII should use MII mode. (Assign the this MII module a signal with twice the period of the MII clock signal.)  


1/3  
Option register/segment added.  


1/4  
Bugfix for "MII" mode.  


1/5  
Add data reject mode and fix data buffering size term.  


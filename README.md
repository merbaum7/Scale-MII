# Scale-MII

### Scalable MII(Media Independent Interface) IF IP
  
7/17  
XGMII[64bit], GMII[8bit], MII[4bit] supported.  


7/18  
For SPIN support, fixed sequence send_mii and recv_mii.  


7/22  
Added data address header, and fixed each seqence.  


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
Added data reject mode and fix data buffering size term.  


1/7  
Fixed xgmii receive function case of receive datasize is 32bit.  
Add receive done signal.  


1/8  
Fixed condition of header received signal.  


1/14  
Increased frame deny condition.  


1/21  
Fixed buffer read sequence.  


1/23  
Added header send end flag and fix send register of mii-mode.  


2/4  
Fixed xgmii send data byte alliance.  
(to fit mii and gmii)  


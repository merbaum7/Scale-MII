# Scale-MII

### Scalable MII(Media Independent Interface) IF IP
  
2025/7/17  
XGMII[64bit], GMII[8bit], MII[4bit] supported.  


2025/7/18  
For SPIN support, fixed sequence send_mii and recv_mii.  


2025/7/22  
Added data address header, and fixed each seqence.  


2025/7/23  
Fixed send/recv sequence. Data size is scaled from the header.  


2025/10/6  
RGMII[4bit] supported.  
Add 25GMII[64bit] mode.  


2025/11/5  
RGMII mode Removed.  
RGMII should use MII mode. (Assign the this MII module a signal with twice the period of the MII clock signal.)  


2026/1/3  
Option register/segment added.  


2026/1/4  
Bugfix for "MII" mode.  


2026/1/5  
Added data reject mode and fix data buffering size term.  


2026/1/7  
Fixed xgmii receive function case of receive datasize is 32bit.  
Add receive done signal.  


2026/1/8  
Fixed condition of header received signal.  


2026/1/14  
Increased frame deny condition.  


2026/1/21  
Fixed buffer read sequence.  


2026/1/23  
Added header send end flag and fix send register of mii-mode.  


2026/2/4  
Fixed xgmii send data byte alliance.  
(to fit mii and gmii)  


2026/5/18  
Change Lisence.  
(From MIT Lisence to SHL-2.1)  


2026/5/20  
Added force send mode.  


2026/6/19  
Fixed the definition of data size.  
(Send/Recv size: size*256byte -> (size+1)*256byte)  


# Scale-MII

### Scalable MII(Media Independent Interface) IF IP
  
7/17  
XGMII[64bit], GMII[8bit], MII[4bit] supported.  


7/18  
Fixed MII receive sequence of recv_mii for correct crc receiving.  


10/6  
RGMII[4bit] supported.  
Add 25GMII[64bit] mode.  


11/5  
RGMII mode Removed.  
RGMII should use MII mode. (Assign the this MII module a signal with twice the period of the MII clock signal.)  

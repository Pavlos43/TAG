#!/usr/bin/python

from TOSSIM import *
import sys ,os, time
import random


if (len(sys.argv) > 1):			#Checks if a document a name of a document has been given 
	topo = sys.argv[1]  
else:					#If not defaults to "topology.txt"
 	topo ="topology.txt"

links = []				
for line in open(topo, "r").readlines():	#Reads document line by line
	s = line.split()			#Splits the line
	if len(s) >= 3:			#If we have three arguments, we pass them to their respective positions
		links.append((int(s[0]), int(s[1]), float(s[2])))

 
if (len(sys.argv) > 2):				#Checks if we were passed the amount of nodes
	N = int(sys.argv[2])
else: 						#If not we calculate it 					
	N = max(max(a,b) for a, b, c in links) + 1

print "Nodes: %d, Topology: %s"% (N,topo)

t=Tossim([])

if (len(sys.argv) > 4):				#We take the seed that was given
	seed = int(sys.argv[4]) 
else:						#We take the time to calculate the seed
	seed = int(time.time())
	
t.randomSeed(seed)
print "Seed:", seed

f=sys.stdout #open('./logfile.txt','w')		
SIM_END_TIME= 800 * t.ticksPerSecond()		#The time the experiment will run

print "TicksPerSecond : ", t.ticksPerSecond(),"\n"

t.addChannel("Boot",f)				#Add a channel for Boot messages
t.addChannel("RoutingMsg",f)			#Add a channel for Routing messages
#t.addChannel("NotifyParentMsg",f)
t.addChannel("Radio",f)				#Add a channel for Radio messages
#t.addChannel("Serial",f)
t.addChannel("SRTreeC",f)			#Add a channel for SRTreeC messages
#t.addChannel("PacketQueueC",f)

randDelay = 0				#Initiallize variable used for the delay				
if(len(sys.argv)>3):			#If there was given an argument we use it to compute the delay
	randDelay = int(sys.argv[3]) % 10
else:					#Else we calculate with the help of the time 
	randDelay = int(time.time()) % 10

for i in range(0,N):			#One by one we boot each node with a 10ms delay
	m=t.getNode(i)
	m.bootAtTime(10*t.ticksPerSecond() + i + randDelay)

r=t.radio()		#We set the radio link quality between the links that were given to us from the topology
for a, b, c in links:
	r.add(a, b, c)

mTosdir = os.getenv("TINYOS_ROOT_DIR")		#We insert a real noise to make our simulation more realistic
noiseF=open(mTosdir+"/tos/lib/tossim/noise/meyer-heavy.txt","r")
lines= noiseF.readlines()[:100]			#We only keep the first 100 lines for speed purposes

for line in  lines:				
	str1=line.strip()
	if str1:
		val=int(str1)
		for i in range(0,N):
			t.getNode(i).addNoiseTraceReading(val)
noiseF.close()
for i in range(0,N):
	t.getNode(i).createNoiseModel()
	
h=True
while(h):				#The experiment starts and does not end until we reach 800 seconds
	try:
		h=t.runNextEvent()
	except:
		print sys.exc_info()

	if (t.time()>= SIM_END_TIME):
		h=False

for a, b, c in links:		#We print at the end of the experiment to check that the connections was created
	print "Node", a, "connected with node", b ,":", r.connected(a,b) , r.connected(b,a)

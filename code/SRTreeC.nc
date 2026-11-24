#include "SimpleRoutingTree.h"

module SRTreeC
{
	uses interface Boot;							//Gives us event booted()

	uses interface SplitControl as RadioControl;	//Responsible for starting and stopping a sub-system

	uses interface Random;									//Used for generating random values
	uses interface ParameterInit<uint16_t> as SeedInit;		//Used to give diffrent seed to each node

	uses interface Packet as RoutingPacket;			//Gives access to the payload of a Routing message
	uses interface AMSend as RoutingAMSend;			//We use to send Routing messages
	uses interface AMPacket as RoutingAMPacket;		//We use to know who sent what
	uses interface Receive as RoutingReceive;			//Receives Routing messages
	uses interface PacketQueue as RoutingSendQueue;		//Used for Routing messages that are waiting to be sent
	uses interface PacketQueue as RoutingReceiveQueue;	//Used for Routing messages that are waiting to be processed

	uses interface Packet as ValuePacket;				//Gives access to the payload of a Value message
	uses interface AMSend as ValueAMSend;				//We use to send Value messages
	uses interface AMPacket as ValueAMPacket;			//We use to know who sent what
	uses interface Receive as ValueReceive;				//Receives Value messages
	uses interface PacketQueue as ValueSendQueue;		//Used for Value messages that are waiting to be sent
	uses interface PacketQueue as ValueReceiveQueue; //Used for Value messages that are waiting to be processed

	uses interface Timer<TMilli> as EpochTimer;				//Used to tell when we change Epochs
	uses interface Timer<TMilli> as RoutingMsgTimer;	//Responsible for sending the Routing messages while the tree is being built

}
implementation
{

	message_t radioRoutingSendPkt;		 //Buffer holding the Routing Message currently being sent

	bool RoutingSendBusy=FALSE;			//True while a "send" is happening

	uint8_t curdepth;					//The depth of the node in the tree
	uint16_t parentID;					//The ID of the parent node

	bool parentLocked;					//True when node has found a parent

	uint8_t function;					//Tells us the fuction(SUM,AVG,VARIANCE,MAX)
	uint8_t epochDuration;				//Duration of an Epoch

	#define SLOT_MS 50					//Time a node is activated
	#define JITTER_MS 30				//Small random variable
	uint32_t slotBase;					//Absolute timestamp (ticks) of our next scheduled "slot"

	bool firstEpochDone = FALSE;		//Helps us know when we have to alter and when to generate a value
	uint8_t my_value;					//The value of a node
	uint16_t aggSum=0;					//The sum
	uint32_t aggSum2=0;					//The sum of the squared values
	uint8_t aggCount=0;					//The count of the contributed nodes
	uint8_t aggMax=0;					//Max value

	#define MAX_CHILDREN 16 			//Max amount of children
	uint16_t childID[MAX_CHILDREN];		//Node Id of every known child
	uint16_t childLastSum[MAX_CHILDREN];	//Last known Sum of the child
	uint32_t childLastSum2[MAX_CHILDREN];	//Last known Sum of the squared values of the child
	uint8_t childLastCount[MAX_CHILDREN];	//Last known Sum of the children that had contributed
	uint8_t childLastMax[MAX_CHILDREN];		//Last known Max of the child
	bool childFresh[MAX_CHILDREN];			//True if the child sends a new value
	uint8_t numChildren = 0;				//Amount of children we have encountered

	message_t radioValueSendPkt;			//Buffer holding the Value Message currently being sent
	bool ValueSendBusy = FALSE;				//True while a "send" is happening

	task void sendRoutingTask();
	task void receiveRoutingTask();

	task void sendValueTask();
	task void receiveValueTask();

	void setRoutingSendBusy(bool state)		//Helper functions for changing the RoutingSendBusy
	{
		atomic{
		RoutingSendBusy=state;
		}
	}

	void setValueSendBusy(bool state)		//Helper functions for changing the ValueSendBusy
	{
		atomic{
		ValueSendBusy=state;
		}
	}

	void startEpochSchedule(){			//Used for calculating the time slots for each depth
	 	uint32_t jitter = 0;			//Initiallization of jitter
		slotBase = (uint32_t) epochDuration * 1024UL - (uint32_t)(curdepth + 1)* SLOT_MS;	//Calculates when each depth "talks", the deeper the level the earlier it talks

		if (TOS_NODE_ID != 0)			//If it is the root it does not need a jitter
			jitter = call Random.rand16()%JITTER_MS;
		call EpochTimer.startOneShotAt(0,slotBase + jitter);
	}

	void scheduleNextEpoch(){			//Calculates the re-activation period based on the previous offset
	 	uint32_t jitter = 0;			//Initiallization of jitter
		slotBase += (uint32_t) epochDuration * 1024UL;		//Adds an Epoch to the previous offset

		if (TOS_NODE_ID != 0)			//If it is the root it does not need a jitter
			jitter = call Random.rand16()%JITTER_MS;
		call EpochTimer.startOneShotAt(slotBase,jitter);
	}

	int8_t childFinder(uint16_t id)		//Finds a child in the cache tables
	{
		uint8_t i;
		for (i=0; i<numChildren; i++)	//Search if we have the id already
		{
			if (childID[i]==id)
			{
				return i;				//It already exists so we return it
			}
		}

		if (numChildren == MAX_CHILDREN)
		{
			return -1;					//The node is full of children
		}

		//New child so we add it with an initial state
		childID[numChildren]=id;
		childLastSum[numChildren]=0;
		childLastSum2[numChildren]=0;
		childLastCount[numChildren]=0;
		childLastMax[numChildren]=0;
		childFresh[numChildren]=FALSE;

		return numChildren++ ;		//We return the new index and increment the count
	}

	event void Boot.booted()		//The node gets initiallized and learns if it is the root or not
	{
		call RadioControl.start();	//Start the radio
#ifdef TOSSIM
		call SeedInit.init((uint16_t)(sim_random() + TOS_NODE_ID));		//Gets a seed from the time
#endif

		setRoutingSendBusy(FALSE);	//Initially no one is sending

		if(TOS_NODE_ID==0)			//Checks whether it is the root and initiallizes it
		{
			curdepth=0;
			parentID=0;
			parentLocked=TRUE;

			my_value = (call Random.rand16() % MAX_SENSOR_VALUE)+1;		//Gets random value set

			function = (call  Random.rand16() % 4)+1;					//Picks randomly the function
			epochDuration = ((call Random.rand16() % 8)+3)*10;			//Picks randomly the Epoch Duration
			dbg("Boot", "Function chosen: type %u, epoch duration: %u sec\n", function, epochDuration);
			startEpochSchedule();										//Starts the Epoch Timer
		}
		else 					//It is not a root
		{
			curdepth=-1;
			parentID=-1;
			parentLocked=FALSE;

			my_value = (call Random.rand16() % MAX_SENSOR_VALUE) + 1;	//Gets random value set
		}
	}

	event void RadioControl.startDone(error_t err)		//Is called after the RadioControl.start is completed
	{
		if (err == SUCCESS)
		{
			dbg("Radio" , "Radio initialized successfully!!!\n");

			if (TOS_NODE_ID==0)		//If it is the root it starts the Routing flood
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		}
		else
		{
			dbg("Radio" , "Radio initialization failed! Retrying...\n");
			call RadioControl.start();				//Retry to open the radio
		}
	}

	event void RadioControl.stopDone(error_t err)		//Is called after the RadioControl.stop is completed
	{
		dbg("Radio", "Radio stopped!\n");
	}

	event void RoutingMsgTimer.fired()					//Makes and send a Routing Message
	{
		message_t tmp;
		error_t enqueueDone;

		RoutingMsg* mrpkt;
		if(call RoutingSendQueue.full())				//Checks whether the sending queue is full
		{
			dbg("SRTreeC" , "Sending Queue is full\n");
			return;
		}


		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));	//Get a typed pointer into tmp's payload

		if(mrpkt==NULL)									//Checks whether the payload fits the RoutingMsg
		{
			return;
		}

		atomic{			//fill in the information needed in the packet
		mrpkt->depth = curdepth;
		mrpkt->packet = PACK_INFO(function,epochDuration);
		}

		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);		//Broadcast
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));		//Check how many bytes of the payload are actually valid

		enqueueDone=call RoutingSendQueue.enqueue(tmp);				//We put the message in the sending queue

		if( enqueueDone==SUCCESS)
		{
			if (call RoutingSendQueue.size()==1)
			{

				post sendRoutingTask();							//If it is the first in the queue it gets sent
			}
		}
	}


	event void RoutingAMSend.sendDone(message_t * msg , error_t err)	//Is called after sending a RoutingMsg is completed
	{

		dbg("SRTreeC" , "Routing Package sent %s \n", (err==SUCCESS)?"True":"False");

		setRoutingSendBusy(FALSE);						//Set the radio not busy again

		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();						//If there is something in the queue we send it
		}
	}


	event void ValueAMSend.sendDone(message_t *msg , error_t err)	//Is called after sending a ValueMsg is completed
	{
		dbg("SRTreeC", "Value Package sent %s \n",(err==SUCCESS)?"True":"False");
		setValueSendBusy(FALSE);

		if(!(call ValueSendQueue.empty()))
		{
			post sendValueTask();						//If there is something in the queue we send it
		}
	}


	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)	//Is called every time a RoutingMsg arrives
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;

		msource =call RoutingAMPacket.source(msg);			//Checks where the message came from
		if (!parentLocked)									//If the node does not have a parent it displays who sent the message
		{
			dbg("SRTreeC", "Package received from %u\n",msource);
		}

		atomic{												//Copy the message
		memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);		//It is put in the Queue
		if(enqueueDone == SUCCESS)
		{
			post receiveRoutingTask();							//It is proccessed
		}
		return msg;												//Return the message
	}


	event message_t* ValueReceive.receive(message_t* msg, void* payload, uint8_t len)	//Is called every time a ValueMsg arrives
	{
		error_t enqueueDone;
		message_t tmp;

		atomic{											//Copy the message
			memcpy(&tmp,msg,sizeof(message_t));
		}

		enqueueDone = call ValueReceiveQueue.enqueue(tmp);		//It is put in the Queue
		if (enqueueDone==SUCCESS)
		{
			post receiveValueTask();							//It is proccessed
		}
		return msg;
	}


	void updateMyValue(){										//Gives new value to the node by giving a +_25% of the original
		int16_t range = ((int16_t) my_value * VALUE_CHANGE_PERCENT) / 100;		//The range of numbers we can select from with the +_25%
		int16_t delta;
		int16_t newVal;

		if (range > 0) {
			delta = (int16_t)(call Random.rand16() % (int16_t)(2*range+1)) - range;		//Picks random delta in the range ([-range,+range])
		}
		else{						//If range=0 that means we have a very small value therefore we do not add anything to the old value
			delta = 0;
		}

		newVal = (int16_t) my_value + delta;	//Calculate new value

		if (newVal < MIN_SENSOR_VALUE){			//Checks the value alligns with the limits set by the assignment
			newVal = MIN_SENSOR_VALUE;
		}

		if (newVal > MAX_SENSOR_VALUE){			//Checks the value alligns with the limits set by the assignment
			newVal = MAX_SENSOR_VALUE;
		}

		my_value = (uint8_t) newVal;			//Gives the new value to our old variable
	}

	event void EpochTimer.fired() 				//Fires once per epoch, at a time that depends on our depth in the tree
	{

		scheduleNextEpoch();								//Schedules the next epoch

		if (firstEpochDone)
		{
			updateMyValue();								//Generates a new value after the first epoch
		}
		else
		{
			firstEpochDone = TRUE;							//Marks that the first epoch has passed
		}

		dbg("SRTreeC","My_value = %u\n", my_value);

		{
			uint8_t i;

			for (i=0; i<numChildren; i++)
			{
				if (!childFresh[i])
				{
					dbg("SRTreeC","Did not receive value from %u, using old one\n", childID[i]);		//Tells us which child did not send a new value this epoch
				}
			}

			switch(function)							//Rebuilds the whole aggregate: our own value + every known child's last known value
		 	{
				case 1:
					aggSum = my_value;					//Starts from our own value
					for (i=0; i<numChildren; i++)
					{
						aggSum += childLastSum[i];		//Adds every child's last known sum
					}
					break;
				case 2:
					aggSum = my_value;
					aggCount = 1;						//Counts ourselves
					for (i=0; i<numChildren; i++)
					{
						aggSum += childLastSum[i];
			 			aggCount += childLastCount[i];	//Adds every child's last known count
			 		}
					break;
				case 3:
					aggSum = my_value;
					aggSum2 = (uint32_t) my_value * my_value;		//Squares our own value
					aggCount = 1;
					for (i=0; i<numChildren; i++)
	 				{
	 					aggSum += childLastSum[i];
		 				aggSum2 += childLastSum2[i]; 	//Adds every child's last known sum of squares
						aggCount += childLastCount[i];
					}
					break;
				case 4:
					aggMax = my_value;					//Starts by assuming our own value is the max
					for (i=0; i<numChildren; i++)
					{
						if (childLastMax[i] > aggMax)
		 				{
							aggMax = childLastMax[i];	//Replaces it if a child's last known max is bigger
						}
					}
					break;
		 	}
			for (i=0; i<numChildren; i++)
			{
				childFresh[i] = FALSE;					//Resets so next epoch starts tracking freshness again
			}
		}

		if (TOS_NODE_ID == 0)
	 	{
	 		switch(function)							//We are the root, so we print the final result instead of sending it onwards
	 		{
				case 1:
	 				dbg("SRTreeC","EPOCH RESULT: SUM = %u\n", aggSum);
	 				break;
				case 2:
				 	dbg("SRTreeC","EPOCH RESULT: AVG = %.4f\n", (double)aggSum / aggCount);
					break;
	 			case 3:
	 			{
	 				double mean = (double)aggSum / aggCount;								//Average of the values
		 			double variance = (double)aggSum2 / aggCount - mean * mean;			//E[X^2] - (E[X])^2
	 				dbg("SRTreeC","EPOCH RESULT: VARIANCE = %.4f\n", variance);
	 				break;
	 			}
	 			case 4:
	 				dbg("SRTreeC","EPOCH RESULT: MAX = %u\n", aggMax);
		 			break;
	 		}
			aggSum=0;				//Resets the accumulators for the next epoch (redundant, kept for safety)
	 		aggSum2=0;
	 		aggCount=0;
	 		aggMax=0;
	 	}
	 	else
	 	{
	 		message_t tmp;
	 		ValueMsg* vmsg;
	 		uint8_t sendLen=0;
	 		vmsg = (ValueMsg*) (call ValuePacket.getPayload(&tmp, sizeof(ValueMsg)));		//Get a typed pointer into tmp's payload
	 		switch(function)								//Packs only the fields needed for our function, to keep the message minimal
	 		{
				case 1:
	 				vmsg->sumMsg.sum = aggSum;
	 				sendLen = sizeof(SumMsg);
	 				dbg("SRTreeC","SUM : %d\n", vmsg->sumMsg.sum);
	 				break;
	 			case 2:
	 				vmsg->avgMsg.sum = aggSum;
	 				vmsg->avgMsg.count = aggCount;
	 				sendLen = sizeof(AvgMsg);
	 				dbg("SRTreeC","AVG :sum =%d, count =%d\n", vmsg->avgMsg.sum, vmsg->avgMsg.count);
	 				break;
	 			case 3:
					vmsg->varianceMsg.sum = aggSum;
	 				vmsg->varianceMsg.sum2count = (aggSum2 << 8) | aggCount;			//Packs sum2 and count into one field
	 				sendLen = sizeof(VarianceMsg);
	 				dbg("SRTreeC","VAR : sum =%d, sum^2 =%d\n", vmsg->varianceMsg.sum, vmsg->varianceMsg.sum2count);
	 				break;
	 			case 4:
					vmsg->maxMsg.max = aggMax;
	 				sendLen = sizeof(MaxMsg);
	 				dbg("SRTreeC","MAX : %d\n", vmsg->maxMsg.max);
	 				break;
			}
	 		call ValueAMPacket.setDestination(&tmp, parentID);			//Sends only to our parent (unicast, not broadcast)
	 		call ValuePacket.setPayloadLength(&tmp, sendLen);
	 		if (call ValueSendQueue.enqueue(tmp) == SUCCESS)
	 		{
	 			if (call ValueSendQueue.size() == 1)
	 			{
	 				post sendValueTask();
	 			}
	 		}
	 		aggSum=0;
	 		aggSum2=0;
	 		aggCount=0;
	 		aggMax=0;
		}
	}

////////////// Tasks implementations //////////////////////////////

	task void sendValueTask() {						//Dequeues and sends the next ValueMsg
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;

		if (call ValueSendQueue.empty())
		{
			return;								//Nothing to send
		}
		if(ValueSendBusy)
		{

			return;								//Already busy with a previous send
		}

		radioValueSendPkt = call ValueSendQueue.dequeue();		//Takes the next message out of the queue

		mlen= call ValuePacket.payloadLength(&radioValueSendPkt);
		mdest=call ValueAMPacket.destination(&radioValueSendPkt);		//Destination was already set to our parent

		sendDone=call ValueAMSend.send(mdest,&radioValueSendPkt,mlen);

		if ( sendDone== SUCCESS)
		{
			setValueSendBusy(TRUE);				//Marks busy until sendDone() fires
		}

	}


	task void receiveValueTask()						//Processes a ValueMsg that arrived from one of our children
	{
		uint8_t len;
		message_t radioValueRecPkt;
		uint8_t idx;
		uint8_t vsrc;

		if (call ValueReceiveQueue.empty()){
			return;									//Nothing to process
		}
		radioValueRecPkt= call ValueReceiveQueue.dequeue();

		if (!call ValueReceiveQueue.empty())
			post receiveValueTask();					//If there is more in the queue, process it next

		vsrc = call ValueAMPacket.source(&radioValueRecPkt);		//Finds out which child sent it
		dbg("SRTreeC", "Received value from %u\n", vsrc);



		if (call EpochTimer.getNow() < slotBase - SLOT_MS)			//Checks if the message arrived after our own slot for this epoch
		{
			dbg("SRTreeC","receiveValueTask(): late message\n");
			return;													//Too late, does not count for this epoch
		}

		idx = childFinder(vsrc);									//Finds (or registers) the child in the cache
		if (idx <0)
		{
			dbg("SRTreeC","receiveValueTask(): full of children\n");
			return;													//No room left for a new child
		}

		len = call ValuePacket.payloadLength(&radioValueRecPkt);

		{
			ValueMsg* vmsg = (ValueMsg*) (call ValuePacket.getPayload(&radioValueRecPkt,len));
			switch(function)										//Stores the value in the matching cache fields for this child
			{
				case 1:
					if (len != sizeof(SumMsg)) return;				//Wrong size, something is off, ignore it
					childLastSum[idx] = vmsg-> sumMsg.sum;
					break;
				case 2:
					if (len != sizeof(AvgMsg)) return;
					childLastSum[idx] = vmsg-> avgMsg.sum;
					childLastCount[idx] = vmsg-> avgMsg.count;
					break;
				case 3:
					if (len != sizeof(VarianceMsg)) return;
					childLastSum[idx] = vmsg-> varianceMsg.sum;
					childLastSum2[idx] = vmsg-> varianceMsg.sum2count >> 8;		//Unpacks sum2 from the top bits
					childLastCount[idx] = vmsg-> varianceMsg.sum2count & 0xFF;		//Unpacks count from the bottom bits
					break;
				case 4:
					if (len != sizeof(MaxMsg)) return;
					childLastMax[idx] = vmsg->maxMsg.max;
					break;
			}
			childFresh[idx] = TRUE;			//Marks that this child sent a fresh value this epoch
		}
	}


	task void sendRoutingTask()						//Dequeues and sends (broadcast) the next RoutingMsg
	{
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;

		if (call RoutingSendQueue.empty())
		{
			//dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");

			return;								//Nothing to send
		}


		if(RoutingSendBusy)
		{
			//dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			return;								//Already busy with a previous send
		}

		radioRoutingSendPkt = call RoutingSendQueue.dequeue();		//Takes the next message out of the queue



		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);
		if(mlen!=sizeof(RoutingMsg))
		{
			//dbg("SRTreeC","\t\tsendRoutingTask(): Unknown message!!!\n");

			return;								//Wrong size, do not send it
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);

		if ( sendDone== SUCCESS)
		{
			setRoutingSendBusy(TRUE);				//Marks busy until sendDone() fires
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");
		}
	}


	task void receiveRoutingTask()						//Processes a RoutingMsg that arrived during the tree-building flood
	{
		uint8_t len;
		message_t radioRoutingRecPkt;

		if (call RoutingReceiveQueue.empty())   // FIX: dequeue xwris elegxo
			return;
		radioRoutingRecPkt = call RoutingReceiveQueue.dequeue();
		if (!call RoutingReceiveQueue.empty())  // FIX: post bug
			post receiveRoutingTask();
		len = call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		if (len==sizeof(RoutingMsg))
		{
			RoutingMsg* mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt, len));
			uint16_t msrc = call RoutingAMPacket.source(&radioRoutingRecPkt);
			if (parentLocked)
			{
				return;							//We already have a parent, so we ignore this message
			}

			function = PACKET_FUNC(mpkt->packet);			//Learns the function from the parent
			epochDuration = PACKET_EPOCH(mpkt->packet);	//Learns the epoch duration from the parent

			parentID = call RoutingAMPacket.source(&radioRoutingRecPkt);		//Locks in the sender as our parent
			curdepth = mpkt->depth + 1;										//Our depth is the parent's depth + 1
			parentLocked = TRUE;
			startEpochSchedule();	//SLOT IMPLEMENTATION
			dbg("SRTreeC" , "Parent found parentID=%d\n", parentID);

			if (TOS_NODE_ID != 0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD + (call Random.rand16() % 40));	//Re-broadcasts our own depth, a bit faster, so the tree grows deeper quicker
			}
		}
		else
		{
			dbg("SRTreeC","receiveRoutingTask(): Empty message \n");
			return;
		}
	}
}

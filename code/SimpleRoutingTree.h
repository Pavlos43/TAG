#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H


enum{
	SENDER_QUEUE_SIZE=3,		//Sending queue size 
	RECEIVER_QUEUE_SIZE=10,		//Receiving queue size
	
	AM_ROUTINGMSG=22,		//AM port for Routing messages
	
	TIMER_FAST_PERIOD=200,		//Period for how often we send Routing messanges
	
	AM_VALUEMSG=40,			//AM port for Value messages		
	MIN_SENSOR_VALUE=1,		//Minimum Value that can be taken by a node
	MAX_SENSOR_VALUE=100,		//Maximum Value that can be taken by a node
	VALUE_CHANGE_PERCENT=25,	//Percentage the Value can change between epochs
};

typedef nx_struct RoutingMsg		//Routing Message: Used for creating the tree
{
	nx_uint8_t depth;		//Depth of sendee
	nx_uint8_t packet;		//Packet of information: function and epoch Duration
} RoutingMsg;

#define PACK_INFO(f,e)	((uint8_t)(((f)-1) | ((((e) / 10) -3) << 2)))	//Packets function and epoch
#define PACKET_FUNC(p)  (((p) & 0x03) +1)			//Unpackets the fuction from the packeted byte
#define PACKET_EPOCH(p) (((((p) >> 2) & 0x07) + 3) * 10)	//Unpackets the fuction from the packeted byte

typedef nx_struct SumMsg		
{
	nx_uint16_t sum;		//Sum
} SumMsg;

typedef nx_struct AvgMsg
{
	nx_uint16_t sum;		//Sum
	nx_uint8_t count;		//Count of how many have been part of the sum 
} AvgMsg;

typedef nx_struct VarianceMsg
{
	nx_uint16_t sum;		//Sum
	nx_uint32_t sum2count;		//Packet of information: Sum^2 and count 
	
} VarianceMsg;

typedef nx_struct MaxMsg
{
	nx_uint8_t max;			//Max
} MaxMsg;		
	
typedef union ValueMsg			//Union of the four struckts so we avoid four diffrent for our payload
{
	SumMsg sumMsg;
	AvgMsg avgMsg;
	VarianceMsg varianceMsg;
	MaxMsg maxMsg;
}ValueMsg;

#endif

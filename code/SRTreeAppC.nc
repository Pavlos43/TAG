#include "SimpleRoutingTree.h"

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;				//Our main module containing our implementation of TAG

	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;		//Sends the signal for creating the tree
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;	//Receives the signal for creating the tree
	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;		//Queue for sent messages
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;	//Queue for received messages

	components new AMSenderC(AM_VALUEMSG) as ValueSenderC;   		//Sends the signal containing the value
	components new AMReceiverC(AM_VALUEMSG) as ValueReceiverC; 		//Receives the signal containing the value
	components new PacketQueueC(SENDER_QUEUE_SIZE) as ValueSendQueueC;			//Queue for sent messages
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as ValueReceiveQueueC;		//Queue for received messages

	components MainC, ActiveMessageC, RandomC;						//Basic TinyOs components

	components new TimerMilliC() as RoutingMsgTimerC;				//Timer for Routing flood
	components new TimerMilliC() as EpochTimerC;					//Timer for Epoch scheduling
	
	//Wiring Components
	
	SRTreeC.Boot->MainC.Boot;
	
	SRTreeC.RadioControl -> ActiveMessageC;

	SRTreeC.Random -> RandomC;
	SRTreeC.SeedInit -> RandomC;

	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
	SRTreeC.EpochTimer->EpochTimerC;

	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;

	SRTreeC.ValuePacket->ValueSenderC.Packet;
	SRTreeC.ValueAMPacket->ValueSenderC.AMPacket;
	SRTreeC.ValueAMSend->ValueSenderC.AMSend;
	SRTreeC.ValueReceive->ValueReceiverC.Receive;
	SRTreeC.ValueSendQueue->ValueSendQueueC;
	SRTreeC.ValueReceiveQueue->ValueReceiveQueueC;	
}

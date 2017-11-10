# CloudHaskellBeginner

This is a beginner project .. I am experimenting first time with Cloud Haskell.

My goal is to implement a distributed system in which:

1: several nodes forms a cluster and send messages (a random number) to each other 
   such that messages from each nodes reaches every other node in the cluster.

2: message sending is being done for a specific amount of time and afterwards message sending stops
   now comes the so called grace period time in which nodes don't send the messages but any unreceived
   message is got received
   Also within this time only node start to print the output which is a tuple
    (|m|,for i = 1 to |m| :sum of {mi * i})
    where
     m is the list of all messages received by each node and ordered by sending time of node
     mi is the i'th message sent by some node or basically i'th element of m i.e. a random number (0,1)

3: after the grace period the program gets killed

My assumptions ::
 
 * I have assumed that the underlying network is quiet rock solid for now
   so almost no failure maps is applicable for the current solution


Solution::

I can see inherently there is broadcasting nature in the problem

So I was trying to build an infrastructure using which every node can broadcast its message to all others

Now after I built the infrastructure for braodcasting messages it was almost simple to turn off the nodes
and stop after a specified amount of time, which also I have immplemented.

Now problem I faced when I have to print the results, which requires arranging 
the messages in the order of sending time which is a fundamental problem in any
distributed programming. So currently I am researching for the solution or 
algorithms to model clock in this type of scenarios for it I am refering to 
Lamport's solution, vector clocks  along with thinking on my own.

Implementing a solution for that will require more time as most of the time I
spend went on learning basics of the distributive programming or message 
passing style ...and also gaining hands on CloudHaskell.




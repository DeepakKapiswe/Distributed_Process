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


Solution:

I can see inherently there is broadcasting nature in the problem

So I am trying to build an infrastructure using which every node can broadcast its message to all others


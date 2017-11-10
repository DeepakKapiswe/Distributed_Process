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

So I was trying to build an infrastructure using which every node 
can broadcast its message to all others

Now after I built the infrastructure for braodcasting messages 
it was simple to turn off the nodes and stop after a specified 
amount of time, which also I have immplemented, it was just a 
matter of time to grasp the library (distributed-process)


Difficulties ::
Now problem I faced when I have to print the results, which requires arranging 
the messages in the order of sending time which is a fundamental problem in any
distributed programming.

I came up with a solution of estimating the clock difference time with first 
introducing a rondom offset to the local clocktime of nodes and then estimating
roundtrip time between all pairs of node, this would have given me an estimate of
the relative clock differences between the nodes.

But after a little more researchand thinking I came upto the point that it will not 
give us the exactness required of thescale we may want to guarantee in distributive 
programing (we may differ in sec's scale which is quiet big from computing's point of view) 

So currently I am researching for better solution or algorithms to model clock or 
ordering in this type of scenarios for it I am refering to Lamport's solution, 
vector clocks  along with thinking on my own.

Implementing a solution for that will require more time as most of the time I
spend went on learning basics of the distributive programming or message 
passing style ...and also gaining hands on CloudHaskell.

For Better or Higher Score::

I came up  with a simple hack of generating the random number list and then 
dividing the list into chunks and giving the sorted chucks to the worker process
to send across ... hoping this will increase the sigma 
 using the fact that
  1*5 + 2*6 + 3*7 > 1*7 +2*6 + 3*5 
 
 But I have not implemented that as I thought this must not be the concern of the test
 interesting part might be implementation of virtual clock as learning to handle APIs
 is not a big thing in my view

About the code::

I have kept my code very simple, I know its not polished Haskell Program
but this was my first program with distributed-process which I have modified to
fit into the given problem..

I also know code is full of flaws and optimisation oppurtunities are being ignored 

Thanks

